import 'package:flutter/material.dart';

Future<bool> confirmLocationConsent(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('위치 사용 동의'),
        content: const SingleChildScrollView(
          child: Text(
            '검색한 식당을 현재 위치에서 가까운 순으로 정렬해요.\n\n'
            '위도·경도는 검색을 위해 먹끼리 서버로 전송해 처리하며, 계정이나 위치 이력으로 DB에 저장하지 않아요. '
            '백그라운드 위치 추적은 하지 않아요.\n\n'
            '선택 동의이며, 허용하지 않아도 식당 이름 검색과 직접추가를 이용할 수 있어요. '
            '동의 후 기기·브라우저의 위치 권한도 허용해 주세요. 내 프로필에서 언제든 끌 수 있어요.',
          ),
        ),
        actions: [
          TextButton(
            key: const Key('decline-location-consent'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('위치 없이 이용'),
          ),
          FilledButton(
            key: const Key('accept-location-consent'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('동의하고 위치 사용'),
          ),
        ],
      ),
    ) ==
    true;
