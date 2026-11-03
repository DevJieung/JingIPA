import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'theme.dart';

/// Only the anonymous emoji herd scrolls; scenery and nearby controls stay put.
class WaitingFarm extends StatefulWidget {
  const WaitingFarm({required this.members, super.key});
  final List<AppUser> members;

  @override
  State<WaitingFarm> createState() => _WaitingFarmState();
}

class _WaitingFarmState extends State<WaitingFarm> {
  final _scroll = ScrollController(keepScrollOffset: false);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = ((box.maxWidth - 32) / 48).floor().clamp(3, 6);
      final overflow = widget.members.length > columns * 2;
      return Semantics(
        container: true,
        label:
            '대기실 동물 친구 ${widget.members.length}명${overflow ? ", 아래로 스크롤해서 확인" : ""}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const Key('waiting-garden-scene'),
              height: 220,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: sageSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: line),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(
                    child: Image.asset(
                      'assets/brand/waiting-garden-v1.webp',
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  if (widget.members.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .8),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            '모두 팟에 참여했어요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: forest, fontSize: 12),
                          ),
                        ),
                      ),
                    )
                  else
                    Positioned(
                      left: 14,
                      right: 10,
                      top: 66,
                      height: 112,
                      child: Scrollbar(
                        controller: _scroll,
                        thumbVisibility: overflow,
                        thickness: 3,
                        radius: const Radius.circular(4),
                        child: GridView.builder(
                          key: const Key('waiting-garden-scroll'),
                          controller: _scroll,
                          primary: false,
                          padding: const EdgeInsets.only(right: 6),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisExtent: 52,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 2,
                              ),
                          itemCount: widget.members.length,
                          itemBuilder: (context, index) {
                            final person = widget.members[index];
                            return ExcludeSemantics(
                              child: SizedBox(
                                key: Key('waiting-${person.id}'),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Positioned(
                                      bottom: 3,
                                      child: Container(
                                        width: 27,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: forest.withValues(alpha: .09),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: forest.withValues(
                                                alpha: .07,
                                              ),
                                              blurRadius: 5,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: index.isEven ? 7 : 2,
                                      ),
                                      child: Text(
                                        person.emoji,
                                        textScaler: TextScaler.noScaling,
                                        style: const TextStyle(
                                          fontFamily: 'NotoColorEmoji',
                                          fontSize: 34,
                                          height: 1.15,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Visibility(
              visible: overflow,
              maintainSize: true,
              maintainState: true,
              maintainAnimation: true,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.unfold_more_rounded, color: muted, size: 16),
                  SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '스크롤해서 친구들 더 보기',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
