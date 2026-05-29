import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../models.dart';
import '../../screens.dart';

class NewsDetailScreen extends StatelessWidget {
  const NewsDetailScreen({super.key, this.article});

  final NewsArticle? article;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final a = article ?? AppData.newsAll.first;
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
                trailing: [GlowIconButton(icon: Icons.share_outlined)],
              ),
              const SizedBox(height: 16),
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
                        child: Image.asset(
                          a.asset ?? 'assets/images/stadium_live.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const EmptyOrErrorImage(label: 'Article image'),
                        ),
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
                            Text('CricPro Staff',
                                style: TextStyle(
                                    color: c.text,
                                    fontWeight: FontWeight.w700)),
                            Text('Nov 29, 2024 • 10:30 AM',
                                style: TextStyle(color: c.muted, fontSize: 13)),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${a.subtitle}\n\nVirat Kohli smashed a magnificent century as India chased down 280 to beat Australia by 4 wickets in the second ODI at Adelaide Oval.\n\nKohli scored 110 off 112 balls, stitching crucial partnerships with Rohit Sharma (52) and KL Rahul (45) to take India home with 8 balls to spare.\n\n"It was a total team effort. The bowlers did really well in the first innings," said Kohli.',
                      style:
                          TextStyle(color: c.muted, fontSize: 16, height: 1.7),
                    ),
                    const SizedBox(height: 18),
                    SectionHeader('Related News'),
                    const SizedBox(height: 12),
                    NewsListCard(
                        article: AppData.newsAll[1],
                        compact: true,
                        onTap: () {}),
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
