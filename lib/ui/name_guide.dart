import 'package:flutter/material.dart';
import 'theme.dart';

const nameGuide =
    '같이 매칭된 동료가 나를 알아볼 수 있는 이름으로 설정해요. '
    '팟 생성 때는 보이지 않으니 실명으로 하셔도 괜찮습니다 :)';

class NameSetupIntro extends StatelessWidget {
  const NameSetupIntro({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('동료가 알아볼 내 이름', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      const NameGuideText(),
    ],
  );
}

class NameGuideText extends StatelessWidget {
  const NameGuideText({super.key});
  @override
  Widget build(BuildContext context) => const Text(
    nameGuide,
    key: Key('name-visibility-guide'),
    style: TextStyle(fontSize: 13, color: muted, height: 1.65),
  );
}
