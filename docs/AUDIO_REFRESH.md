# ElevenLabs 오디오 교체

2026-09-14 사용자 요청으로 기존 효과음 42개를 전부 교체하고 카드 수집·소환 충전·소환 폭발·합성 충전·합성 폭발 효과음 5개와 BGM 4곡을 추가했다.

| 음원 | 사용 화면 | 반복 길이 |
| --- | --- | --- |
| `art/bgm/camp.ogg` | 타이틀, 야영지, 테마, 종료 | 약 58초 |
| `art/bgm/ritual.ogg` | 카드 선택, 마녀 소환, 배치 준비 | 약 58초 |
| `art/bgm/battle.ogg` | 일반 전투 | 약 58초 |
| `art/bgm/boss.ogg` | 10탄마다 보스 전투 | 약 46초 |

생성 원본과 전체 요청은 `art/audio_sources/elevenlabs_v1/`에 보존한다. `art/audio-manifest.json`에는 공급자, 모델, 프롬프트, 소스 및 출고 파일 SHA-256, 길이, peak/RMS, 루프 접점 검증값을 기록했다. 음악은 `music_v1`, 효과음은 `eleven_text_to_sound_v2`를 사용했다. API: [음악 생성](https://elevenlabs.io/docs/api-reference/music/compose), [효과음 생성](https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert).

`tools/audio/generate_elevenlabs.py --install`은 `.env`의 `ELEVENLABS_API_KEY`를 직접 읽으며 키를 출력하지 않는다. 이미 성공한 원본은 재사용한다. 음악의 마지막 2초와 처음 2초를 겹쳐 이음부를 만들고, -20 LUFS로 정리한 Ogg Vorbis를 출고한다. 효과음은 시작·끝 무음을 정리한 44.1kHz WAV이며, 반복 빈도가 높은 타격·발사 소리는 별도의 낮은 peak로 맞춘다. 원본과 `.env`는 APK에서 제외한다.

`core/sound.gd`가 두 음악 플레이어로 1.2초 장면 전환을 처리한다. 동일 곡 재요청은 재시작하지 않는다. 메뉴의 효과음과 배경음악 설정은 별도로 저장되며, 광고 및 앱 백그라운드 진입 중 재생을 정지하고 복귀 시 이어간다. 소환 효과음은 `card_collect`, `summon_charge`, `summon_burst`, `fusion_charge`, `fusion_burst`다.

검증:

- `python3 tools/audio/check_audio.py`: BGM 4곡과 효과음 47개 전부 디코딩, 유효 신호, 클리핑, 시작/끝, 무음 구간, 루프 접점, 생성 소스 일치 확인.
- `POCKER_NO_SAVE=1 POCKER_AUDIO_TEST=1 godot --headless --path . res://tests/audio_check.tscn`: 77건 통과. 실제 스트림 반복, 동일 곡 유지, 페이드, 설정 독립성, 광고·앱 전환 정지/재개, 효과음 로딩 확인.
- `tests/flow_check.gd`: 음악 설정의 파일 저장·복원 포함.

Android 기기 스피커에서의 청취 평가는 아직 수행하지 않았다.
