import { cacheGetOrFetch, KEYS, TTL } from '../lib/redis.js';
import providerManager from '../providers/provider-manager.js';
import { cacheMiddleware } from '../middleware/cache.js';

export default async function newsRoutes(fastify) {
  function storyToVideo(story) {
    return {
      videoId: String(story.id || ''),
      title: story.headline || '',
      thumbnail: story.imageUrl || '',
      duration: null,
      category: story.storyType || story.context || '',
      publishedAt: story.publishedTime || '',
      source: 'Cricbuzz',
      videoUrl: null,
      matchId: null,
      seriesId: null,
    };
  }

  // GET /news
  fastify.get('/news', {
    schema: {
      description: 'Get cricket news stories with pagination',
      tags: ['News'],
      querystring: {
        type: 'object',
        properties: {
          cursor: { type: 'string', description: 'Pagination cursor (story ID)' },
          limit: { type: 'integer', minimum: 1, maximum: 50, default: 10 },
          context: { type: 'string', description: 'Filter by context (e.g. IPL 2026)' },
          storyType: { type: 'string', description: 'Filter by story type (e.g. News, Features)' },
        },
      },
      response: {
        200: {
          type: 'object',
          properties: {
            success: { type: 'boolean' },
            data: {
              type: 'object',
              properties: {
                stories: { type: 'array' },
                nextCursor: { type: 'string', nullable: true },
                nextPaginationURL: { type: 'string', nullable: true },
              },
            },
            message: { type: 'string', nullable: true },
          },
        },
      },
    },
  }, async (request, reply) => {
    const { cursor, limit = 10, context, storyType } = request.query;
    const effectiveCursor = cursor || 'default';

    try {
      const { data } = await cacheGetOrFetch(
        KEYS.newsList(effectiveCursor),
        TTL.NEWS_LIST,
        async () => {
          const result = await providerManager.execute('getNewsStories', cursor || undefined);
          return result.data;
        }
      );

      if (!data || !data.stories) {
        return { success: true, data: { stories: [], nextCursor: null, nextPaginationURL: null }, message: 'No news available' };
      }

      let stories = data.stories;

      // Apply filters
      if (context) {
        stories = stories.filter((s) => s.context && s.context.toLowerCase().includes(context.toLowerCase()));
      }
      if (storyType) {
        stories = stories.filter((s) => s.storyType && s.storyType.toLowerCase() === storyType.toLowerCase());
      }

      // Apply limit
      stories = stories.slice(0, limit);

      return {
        success: true,
        data: {
          stories,
          nextCursor: data.nextCursor || null,
          nextPaginationURL: data.nextPaginationURL || null,
        },
        message: null,
      };
    } catch {
      return {
        success: true,
        data: { stories: [], nextCursor: null, nextPaginationURL: null },
        message: 'News data not available',
      };
    }
  });

  // GET /news/:id
  fastify.get('/news/:id', {
    schema: {
      description: 'Get news story detail by ID. Returns summary from list (full body not available from Cricbuzz JSON API).',
      tags: ['News'],
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
        required: ['id'],
      },
      response: {
        200: {
          type: 'object',
          properties: {
            success: { type: 'boolean' },
            data: { type: 'object', nullable: true },
            message: { type: 'string', nullable: true },
          },
        },
      },
    },
  }, async (request, reply) => {
    const { id } = request.params;

    try {
      // Try to find the story from cached news lists
      const { data } = await cacheGetOrFetch(
        KEYS.newsDetail(id),
        TTL.NEWS_DETAIL,
        async () => {
          // Fetch recent stories and find the one with matching ID
          const result = await providerManager.execute('getNewsStories');
          const stories = result.data?.stories || [];
          const story = stories.find((s) => s.id === id);
          if (story) {
            return {
              ...story,
              content: null, // Full body not available from Cricbuzz JSON API
              author: null,
              relatedStories: stories
                .filter((s) => s.id !== id && s.context === story.context)
                .slice(0, 3)
                .map((s) => ({ id: s.id, headline: s.headline, context: s.context, publishedTime: s.publishedTime, imageUrl: s.imageUrl })),
            };
          }
          return null;
        }
      );

      if (!data) {
        return reply.code(404).send({
          success: false,
          data: null,
          message: 'Story not found. Full article body is not available from Cricbuzz JSON API.',
        });
      }

      return {
        success: true,
        data,
        message: data.content === null ? 'Full article body not available from Cricbuzz JSON API. Showing summary.' : null,
      };
    } catch {
      return reply.code(404).send({
        success: false,
        data: null,
        message: 'Story not found',
      });
    }
  });

  // GET /videos — app-safe video list. Cricbuzz video URLs are not available
  // through the current JSON source, so videoUrl is nullable.
  fastify.get('/videos', {
    schema: {
      description: 'Get cricket video cards where available',
      tags: ['News'],
      querystring: {
        type: 'object',
        properties: {
          limit: { type: 'integer', minimum: 1, maximum: 50, default: 10 },
        },
      },
    },
  }, async (request) => {
    const { limit = 10 } = request.query;
    try {
      const { data } = await cacheGetOrFetch(
        KEYS.newsList('videos-default'),
        TTL.NEWS_LIST,
        async () => (await providerManager.execute('getNewsStories')).data
      );
      const stories = data?.stories || [];
      const videos = stories.slice(0, limit).map(storyToVideo);
      return {
        success: true,
        data: videos,
        message: videos.length === 0 ? 'Videos not available from provider' : null,
      };
    } catch {
      return { success: true, data: [], message: 'Videos not available from provider' };
    }
  });

  // GET /videos/:id
  fastify.get('/videos/:id', {
    schema: {
      description: 'Get a cricket video card by ID',
      tags: ['News'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request, reply) => {
    const { id } = request.params;
    try {
      const { data } = await cacheGetOrFetch(
        KEYS.newsList('videos-default'),
        TTL.NEWS_LIST,
        async () => (await providerManager.execute('getNewsStories')).data
      );
      const story = (data?.stories || []).find((s) => String(s.id) === String(id));
      if (!story) return reply.code(404).send({ success: false, data: null, message: 'Video not found' });
      return { success: true, data: storyToVideo(story), message: 'Provider does not expose playable videoUrl yet' };
    } catch {
      return reply.code(404).send({ success: false, data: null, message: 'Video not found' });
    }
  });
}
