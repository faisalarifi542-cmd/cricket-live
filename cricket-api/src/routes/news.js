import { cacheGetOrFetch, cacheSet, KEYS, TTL } from '../lib/redis.js';
import providerManager from '../providers/provider-manager.js';

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
    const effectiveCursor = cursor ? String(cursor).trim() : '';
    const cacheKey = KEYS.newsList(`v3:${effectiveCursor || 'latest'}:${context || 'all'}:${storyType || 'all'}:${limit}`);

    try {
      const { data } = await cacheGetOrFetch(
        cacheKey,
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
      description: 'Get news story detail by ID.',
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
            data: {
              type: 'object',
              nullable: true,
              additionalProperties: true,
              properties: {
                id: { type: 'string' },
                headline: { type: 'string' },
                intro: { type: 'string' },
                body: { type: 'string', nullable: true },
                paragraphs: { type: 'array', items: { type: 'string' } },
                source: { type: 'string' },
                context: { type: 'string' },
                publishedTime: { type: 'string' },
                imageUrl: { type: 'string' },
                imageId: { type: 'string', nullable: true },
                storyType: { type: 'string' },
                storyUrl: { type: 'string' },
                relatedStories: {
                  type: 'array',
                  items: {
                    type: 'object',
                    additionalProperties: true,
                  },
                },
              },
            },
            message: { type: 'string', nullable: true },
          },
        },
      },
    },
  }, async (request, reply) => {
    const { id } = request.params;
    const normalize = (value) => String(value || '').trim();
    const matchesId = (story) =>
      normalize(story?.id) === normalize(id) ||
      normalize(story?.newsId) === normalize(id);
    const resolveStory = async () => {
      const result = await providerManager.execute('getNewsStories');
      const stories = result.data?.stories || [];
      let story = stories.find(matchesId);
      if (!story) {
        story = stories.find((s) =>
          normalize(s.headline)
            .toLowerCase()
            .includes(normalize(id).toLowerCase())
        );
      }
      if (!story) return null;

      const detailResult = await providerManager.execute('getNewsDetail', id, story).catch(() => null);
      const detail = detailResult?.data || null;
      const relatedStories = stories
        .filter((s) => normalize(s.id) !== normalize(id) && s.context === story.context)
        .slice(0, 3)
        .map((s) => ({
          id: s.id,
          headline: s.headline,
          context: s.context,
          publishedTime: s.publishedTime,
          imageUrl: s.imageUrl,
        }));

      if (detail) {
        return {
          ...story,
          ...detail,
          relatedStories: detail.relatedStories?.length ? detail.relatedStories : relatedStories,
        };
      }

      return {
        ...story,
        body: story.body || story.intro || story.summary || '',
        paragraphs: story.body ? String(story.body).split(/\n{2,}/).filter(Boolean) : [],
        relatedStories,
      };
    };

    try {
      // Try cached detail first, but fall back to a live lookup if the cache
      // only contains an empty placeholder from an older deploy.
      const detailCacheKey = KEYS.newsDetail(`v2:${id}`);
      const cached = await cacheGetOrFetch(
        detailCacheKey,
        TTL.NEWS_DETAIL,
        resolveStory
      );
      let data = cached.data;
      if (!data || !data.headline) {
        data = await resolveStory();
        if (data) {
          await cacheSet(detailCacheKey, data, TTL.NEWS_DETAIL);
        }
      }

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
        message: data.body ? null : 'Full article body not available from provider.',
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
        KEYS.newsList('v2:videos-default'),
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
        KEYS.newsList('v2:videos-default'),
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
