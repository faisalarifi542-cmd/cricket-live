import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../models.dart';

class NewsDetailScreen extends StatelessWidget {
  const NewsDetailScreen({super.key, this.article});

  final NewsArticle? article;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final a = article;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
                context.horizontalPadding, context.detailBottomPadding),
            children: [
              AppHeader(
                leading: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded, color: c.text)),
                title: 'News Detail',
                trailing: const [GlowIconButton(icon: Icons.share_outlined)],
              ),
              const SizedBox(height: 16),
              if (a == null)
                PremiumCard(
                  padding: const EdgeInsets.all(22),
                  child: Text(
                    'Select a news story to view details.',
                    style:
                        TextStyle(color: c.muted, fontWeight: FontWeight.w800),
                  ),
                )
              else
                PremiumCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                          height: 210,
                          width: double.infinity,
                          child: _ArticleImage(source: a.asset),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(a.title,
                          style: TextStyle(
                              color: c.text,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              height: 1.1)),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const CircleAvatar(
                              radius: 18,
                              backgroundColor: Color(0xff0a2748),
                              child: Icon(Icons.edit, size: 18)),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.source,
                                  style: TextStyle(
                                      color: c.text,
                                      fontWeight: FontWeight.w700)),
                              Text(a.date,
                                  style:
                                      TextStyle(color: c.muted, fontSize: 13)),
                            ],
                          )
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        a.subtitle,
                        style: TextStyle(
                            color: c.muted, fontSize: 16, height: 1.7),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArticleImage extends StatelessWidget {
  const _ArticleImage({this.source});

  final String? source;

  @override
  Widget build(BuildContext context) {
    final src = source?.trim() ?? '';
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return Image.network(
        src,
        fit: BoxFit.cover,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (_, __, ___) =>
            const EmptyOrErrorImage(label: 'Article image'),
      );
    }
    return Image.asset(
      src.isEmpty ? 'assets/images/stadium_live.png' : src,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const EmptyOrErrorImage(label: 'Article image'),
    );
  }
}
