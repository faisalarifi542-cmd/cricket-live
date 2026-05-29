import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../models.dart';
import '../../screens.dart';

class HighlightsPlayerScreen extends StatelessWidget {
  const HighlightsPlayerScreen({super.key, this.video});

  final VideoHighlight? video;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final v = video ?? AppData.topMoments.first;
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
                title: 'Highlights',
                trailing: [GlowIconButton(icon: Icons.more_horiz_rounded)],
              ),
              const SizedBox(height: 16),
              FeaturedVideoCard(video: v, onTap: () {}, largeOnly: true),
              const SizedBox(height: 18),
              Text(v.title,
                  style: TextStyle(
                      color: c.text,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1.15)),
              const SizedBox(height: 10),
              Text('${v.match} • ${v.views}',
                  style: TextStyle(color: c.muted, fontSize: 15)),
              const SizedBox(height: 18),
              Text(
                  'This premium player opens from Highlights, Scorecards and Top Moments. Wire in the final video backend later; the UI shell and transitions are ready in this redesign branch.',
                  style: TextStyle(color: c.muted, height: 1.6)),
            ],
          ),
        ),
      ),
    );
  }
}
