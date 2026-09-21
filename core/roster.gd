extends RefCounted
class_name Roster

## 캐릭터·몬스터·테마 표. **자동 생성 파일이다 — 손으로 고치지 마라.**
## 원본은 tools/roster.json 이고, `python3 tools/gen_roster.py` 가 이 파일을 찍어 낸다.
## h(그림 높이)는 tools/gen_art.py 가 실제로 저장하는 크기와 같은 값이다.

## 등급별 이름. 인덱스가 Poker.Hand 값과 같다.
const TIER_KO := ["하이카드", "원페어", "투페어", "트리플", "스트레이트", "플러시", "풀하우스", "포카드", "스트레이트플러시", "로열플러시"]

## 캐릭터 50명(등급마다 5). tier 는 Poker.Hand 값이다.
##
## sc 는 **그림 크기 보정**이다. gen_art.py 는 그림을 등급마다 같은 높이로 저장하는데,
## 그 높이는 지팡이·꼬리·회오리까지 포함한 **테두리 상자**의 높이다. 그래서 소품이 큰
## 캐릭터는 사람 몸이 그만큼 작게 나온다 — 같은 등급인데 누구는 크고 누구는 작아 보인다.
## sc 가 그 몫을 되돌린다(1.0 이 보정 없음). 값은 tools/roster.json 에 손으로 적는다.
##
## role 은 **역할** 넷 중 하나다(Balance.ROLE) — 사용자가 정한 축이다:
##   single 일격 · ricochet 도탄 · rider 특효 · area 광역.
##   ★ 방식(bullet)과 **다른 축**이다. 방식은 「어떻게 닿는가」이고 역할은 「무엇으로
##   값을 하는가」다 — 같은 shot 이라도 일격은 한 대가 무겁고(x1.26) 특효는 가벼운
##   대신(x0.74) 상태이상이 2.2배다. **역할은 무기가 정한다** — 검·총=일격 · 활=도탄 · 채찍=특효 · 광역=광역.
##
## weapon 은 손에 든 것이다. ★ **자세가 여기서 나온다** — gen_art.pose_for() 가
##   활·석궁·총·대포는 겨누는 3/4 옆면으로, 던지는 것은 뒤로 당긴 자세로, 나머지는
##   한 팔을 앞으로 뻗은 시전 자세로 뽑는다. **광역(zone)만은 무기와 상관없이
##   두 팔을 머리 위로 든다**(사용자가 정한 연출).
##
## elem 은 **공격 속성**이다(Balance.ELEM). 무상성(none)은 어떤 몸에도 1.0 배 —
## 활·총·대포·표창이 여기 든다. 나머지 넷은 몬스터의 몸(Balance.MBODY)에 따라
## 2배(약점)·0.5배(저항)·0배(면역)가 된다. 곱하는 곳은 BattleSim._hurt() 한 군데뿐이다.
## ★ **속성이 상태이상도 정한다** — 얼음은 늦추고, 불은 태우고, 전기는 확률로 마비시킨다.
##
## en 은 **화면에 뜨는 이름**이다(영문). ko 는 설명 팝업에만 부제로 남는다 —
## 이름이 두 곳에 있으면 반드시 한 곳만 고치게 되므로, 화면은 en 하나만 본다.
## lore 는 설명 팝업에 뜨는 한 줄 소개다.
##
## anim 은 Idle/Attack/Shot 클립 묶음이 있는 곳이다. 없으면 빈 문자열이고,
## 그때는 정지 그림(art) 한 장만 쓴다 — 그림이 아직 안 나온 캐릭터도 게임은 돈다.
##
## muz 는 **탄이 나가는 자리**다 — 발밑 가운데에서 잰 [가로, 세로]이고 단위는 그림
## 높이(h)의 배수다. 세로는 위가 음수다. **가로의 부호가 곧 그림이 바라보는 쪽**이라
## 음수면 왼쪽을 겨눈 그림이고, 화면이 그런 그림만 좌우로 뒤집어 목표를 보게 한다.
## ★ 손으로 적은 값이 아니라 클립의 **놓는 칸**에서 그대로 잰 값이다
##   (art/anim/<id>/anim.json 의 muzzle_at). 그래서 총구 불꽃과 탄이 늘 같은 자리다.
## wind 는 팔을 뻗는 데 걸리는 시간(초) — 그 클립이 놓는 칸에 닿는 데 걸리는 시간이다.
## 전투는 쏘기로 정한 뒤 이만큼 **기다렸다가** 탄을 내보낸다. 안 그러면 팔을 뻗기도
## 전에 탄이 나가서 몸짓과 사건이 따로 논다.
const UNITS := [
	# --- 하이카드 ---
	{"id": "limne", "ko": "림네", "en": "Limne", "tier": 0, "role": "area", "profile": "balance", "bullet": "zone", "weapon": "deck", "elem": "water", "desc": "물동이를 뒤집어 웅덩이를 깐다", "lore": "단수된 골목에 마지막까지 물을 날랐다. 가장 먼저 불려 나오는 수호자가 주민들의 얼굴을 가장 많이 기억한다.", "color": "#2AC4FF", "h": 96, "sc": 1.00, "muz": [0.3109, -0.6995], "wind": 0.500, "art": "res://art/units/limne.png", "anim": "res://art/anim/limne/"},
	{"id": "chispa", "ko": "치스파", "en": "Chispa", "tier": 0, "role": "single", "profile": "heavy", "bullet": "shot", "weapon": "gun", "elem": "fire", "desc": "부싯돌 한 발로 불을 붙인다", "lore": "대피소 취사장의 불을 처음 되살린 견습공. 작은 화력이라도 꺼지지 않게 돌보는 것이 자기 일이다.", "color": "#FF6A1A", "h": 96, "sc": 1.00, "muz": [0.2234, -0.7128], "wind": 0.500, "art": "res://art/units/chispa.png", "anim": "res://art/anim/chispa/"},
	{"id": "lind", "ko": "린드", "en": "Lind", "tier": 0, "role": "rider", "profile": "rapid", "bullet": "ricochet", "weapon": "whip", "elem": "ice", "desc": "고드름 사슬을 짧게 후려친다", "lore": "빙고 창고 문을 잠그던 막내 관리인. 서리줄을 쳐 물자가 굴러 떨어지는 것을 막던 기술을 적에게 쓴다.", "color": "#5CE8FF", "h": 96, "sc": 1.00, "muz": [0.4511, -0.6576], "wind": 0.500, "art": "res://art/units/lind.png", "anim": "res://art/anim/lind/"},
	{"id": "brigid", "ko": "브리지드", "en": "Brigid", "tier": 0, "role": "ricochet", "profile": "balance", "bullet": "ricochet", "weapon": "bow", "elem": "elec", "desc": "방전 화살이 옆으로 한 번 뛴다", "lore": "끊긴 전선에 임시 연결줄을 쏘던 수습 기사. 아직 먼 곳까지는 못 잇지만 바로 옆 한 사람은 놓치지 않는다.", "color": "#C8FF2E", "h": 96, "sc": 1.00, "muz": [0.4309, -0.7642], "wind": 0.500, "art": "res://art/units/brigid.png", "anim": "res://art/anim/brigid/"},
	{"id": "pip", "ko": "핍", "en": "Pip", "tier": 0, "role": "single", "profile": "rapid", "bullet": "shot", "weapon": "sword", "elem": "none", "desc": "종이 칼날이 쉴 새 없이 나간다", "lore": "카지노 수리용으로 만들어졌지만 피난민들이 붙여 준 이름을 가장 소중히 여긴다. 자기 키보다 낮은 틈을 맡는다.", "color": "#F03BC0", "h": 96, "sc": 1.00, "muz": [0.6944, -0.6111], "wind": 0.583, "art": "res://art/units/pip.png", "anim": "res://art/anim/pip/"},
	# --- 원페어 ---
	{"id": "phorkys", "ko": "포르키스", "en": "Phorkys", "tier": 1, "role": "single", "profile": "balance", "bullet": "shot", "weapon": "gun", "elem": "water", "desc": "물총 여섯 발, 마지막이 꿰뚫는다", "lore": "항만 펌프장이 멈췄을 때 수동으로 밤을 버틴 정비반장. 탄 수를 세며 싸우는 버릇이 있다.", "color": "#1C9BE5", "h": 101, "sc": 1.00, "muz": [0.3109, -0.7409], "wind": 0.417, "art": "res://art/units/phorkys.png", "anim": "res://art/anim/phorkys/"},
	{"id": "solana", "ko": "솔라나", "en": "Solana", "tier": 1, "role": "ricochet", "profile": "balance", "bullet": "shot", "weapon": "bow", "elem": "fire", "desc": "불화살이 세 번 쌓이면 터진다", "lore": "폭풍에 끊긴 대피 항로를 신호탄으로 이어 준 궁수. 가장 멀리 보이는 불이 가장 안전한 길이던 때를 기억한다.", "color": "#FF9226", "h": 101, "sc": 1.00, "muz": [0.3778, -0.7333], "wind": 0.500, "art": "res://art/units/solana.png", "anim": "res://art/anim/solana/"},
	{"id": "jokull", "ko": "요쿨", "en": "Jokull", "tier": 1, "role": "single", "profile": "heavy", "bullet": "pierce", "weapon": "sword", "elem": "ice", "desc": "빙검이 지나간 바닥이 빙판이 된다", "lore": "겨울 산길에 구조 통로를 내던 개척대원. 넘어질 사람을 위해 미끄러운 길에도 반드시 발 디딜 곳을 남긴다.", "color": "#7FD9FF", "h": 101, "sc": 1.00, "muz": [0.6494, -0.6104], "wind": 0.750, "art": "res://art/units/jokull.png", "anim": "res://art/anim/jokull/"},
	{"id": "rhiannon", "ko": "리아넌", "en": "Rhiannon", "tier": 1, "role": "rider", "profile": "balance", "bullet": "chain", "weapon": "whip", "elem": "elec", "desc": "맞은 놈들이 전선으로 이어진다", "lore": "꺼진 골목의 전등을 하나씩 이어 켜던 배선공. 연결된 것들이 함께 버틴다는 믿음을 공격 기술로 쓴다.", "color": "#9B5CFF", "h": 101, "sc": 1.00, "muz": [0.3621, -0.7874], "wind": 0.500, "art": "res://art/units/rhiannon.png", "anim": "res://art/anim/rhiannon/"},
	{"id": "mimic", "ko": "미믹", "en": "Mimic", "tier": 1, "role": "area", "profile": "balance", "bullet": "zone", "weapon": "deck", "elem": "none", "desc": "속성이 매번 달라지는 폭발", "lore": "카지노 물품을 운반하던 인형이 압착기를 바꿔 달았다. 사람을 안을 때는 압력을 가장 낮은 칸에 둔다.", "color": "#B84FFF", "h": 101, "sc": 1.00, "muz": [0.1875, -0.6458], "wind": 0.500, "art": "res://art/units/mimic.png", "anim": "res://art/anim/mimic/"},
	# --- 투페어 ---
	{"id": "protea", "ko": "프로테아", "en": "Protea", "tier": 2, "role": "ricochet", "profile": "rapid", "bullet": "ricochet", "weapon": "bow", "elem": "water", "desc": "세 발이 저마다 다른 길로 간다", "lore": "안개 속에서 구조선 세 척을 동시에 인도하던 항로사. 누구 하나 남기지 않으려 세 목표를 함께 겨눈다.", "color": "#1CE5C0", "h": 106, "sc": 1.00, "muz": [0.4094, -0.7485], "wind": 0.500, "art": "res://art/units/protea.png", "anim": "res://art/anim/protea/"},
	{"id": "ceniza", "ko": "세니자", "en": "Ceniza", "tier": 2, "role": "rider", "profile": "balance", "bullet": "splash", "weapon": "whip", "elem": "fire", "desc": "재구름이 눈을 가린다", "lore": "불탄 거리에서 길을 치우던 청소반장. 살아 있는 사람이 지나갈 한 줄을 남기기 위해 싸운다.", "color": "#E5231C", "h": 106, "sc": 1.00, "muz": [0.1272, -0.6069], "wind": 0.667, "art": "res://art/units/ceniza.png", "anim": "res://art/anim/ceniza/"},
	{"id": "vidarr", "ko": "비다르", "en": "Vidarr", "tier": 2, "role": "area", "profile": "heavy", "bullet": "zone", "weapon": "deck", "elem": "ice", "desc": "발을 굴러 앞을 얼린다", "lore": "붕괴 직전의 교각 아래를 얼려 대피 시간을 벌었다. 말 대신 자기 발이 버티는 곳을 가리킨다.", "color": "#23E0FF", "h": 106, "sc": 1.00, "muz": [0.2010, -0.6340], "wind": 0.583, "art": "res://art/units/vidarr.png", "anim": "res://art/anim/vidarr/"},
	{"id": "finn", "ko": "핀", "en": "Finn", "tier": 2, "role": "single", "profile": "rapid", "bullet": "shot", "weapon": "sword", "elem": "elec", "desc": "짧은 뇌검이 두 번 찌른다", "lore": "달리는 전차에 전력을 넘겨 주던 기동 정비공. 망설이기 전에 손이 먼저 나가지만 두 번째 동작은 정확하다.", "color": "#D6F01D", "h": 106, "sc": 1.00, "muz": [0.5156, -0.5677], "wind": 0.417, "art": "res://art/units/finn.png", "anim": "res://art/anim/finn/"},
	{"id": "dummy", "ko": "더미", "en": "Dummy", "tier": 2, "role": "single", "profile": "balance", "bullet": "shot", "weapon": "gun", "elem": "none", "desc": "효과 없이 정직한 세 점사", "lore": "카지노 폐장 뒤를 순찰하던 경비 인형. 정해진 길을 벗어나지 못하던 몸이 지금은 피난 통로를 지킨다.", "color": "#FF5CE0", "h": 106, "sc": 1.00, "muz": [0.4840, -0.7872], "wind": 0.417, "art": "res://art/units/dummy.png", "anim": "res://art/anim/dummy/"},
	# --- 트리플 ---
	{"id": "marea", "ko": "마레아", "en": "Marea", "tier": 3, "role": "rider", "profile": "balance", "bullet": "splash", "weapon": "whip", "elem": "water", "desc": "반원 물결이 밀어낸다", "lore": "침수 구역에서 사람들을 끌어내던 현장 대장. 공격 후 호스를 잡아당기는 복귀 동작도 구조 작업 그대로다.", "color": "#1DF0A4", "h": 111, "sc": 1.00, "muz": [0.4301, -0.6995], "wind": 0.583, "art": "res://art/units/marea.png", "anim": "res://art/anim/marea/"},
	{"id": "igni", "ko": "이그니", "en": "Igni", "tier": 3, "role": "single", "profile": "balance", "bullet": "pierce", "weapon": "sword", "elem": "fire", "desc": "부채꼴 화염 참격이 줄지어 뚫는다", "lore": "무너진 전차 문을 절단해 승객을 꺼내던 검사. 허세 섞인 인사 뒤에는 늘 탈출로부터 확인한다.", "color": "#F0451D", "h": 111, "sc": 1.00, "muz": [0.6258, -0.6516], "wind": 0.667, "art": "res://art/units/igni.png", "anim": "res://art/anim/igni/"},
	{"id": "kari", "ko": "카레", "en": "Kari", "tier": 3, "role": "single", "profile": "rapid", "bullet": "splash", "weapon": "gun", "elem": "ice", "desc": "냉기 산탄이 부채꼴로 얼린다", "lore": "냉동 창고 연무 속에서 길을 찾던 경비원. 보이지 않는 적을 무작정 쫓지 않고 가까운 공간부터 확보한다.", "color": "#5CE8FF", "h": 111, "sc": 1.00, "muz": [0.3421, -0.7105], "wind": 0.667, "art": "res://art/units/kari.png", "anim": "res://art/anim/kari/"},
	{"id": "donn", "ko": "도난", "en": "Donn", "tier": 3, "role": "area", "profile": "balance", "bullet": "zone", "weapon": "deck", "elem": "elec", "desc": "낙뢰가 젖은 놈부터 찾아간다", "lore": "번개가 치는 날에도 꼭대기 전선을 점검하던 접지공. 위험한 전류가 사람을 피해 흐를 길을 먼저 만든다.", "color": "#B6F01D", "h": 111, "sc": 1.00, "muz": [0.3487, -0.5590], "wind": 0.583, "art": "res://art/units/donn.png", "anim": "res://art/anim/donn/"},
	{"id": "echo", "ko": "에코", "en": "Echo", "tier": 3, "role": "ricochet", "profile": "balance", "bullet": "shot", "weapon": "bow", "elem": "none", "desc": "잔상이 같은 화살을 한 번 더 쏜다", "lore": "대피소 치수를 재던 계측기사. 첫 기록이 틀릴 수 있어 언제나 한 번 더 확인하던 버릇이 무기가 됐다.", "color": "#E84FE0", "h": 111, "sc": 1.00, "muz": [0.4362, -0.7651], "wind": 0.500, "art": "res://art/units/echo.png", "anim": "res://art/anim/echo/"},
	# --- 스트레이트 ---
	{"id": "glaukos", "ko": "글라우코스", "en": "Glaukos", "tier": 4, "role": "single", "profile": "balance", "bullet": "pierce", "weapon": "sword", "elem": "water", "desc": "올려베면 물기둥이 솟는다", "lore": "무너진 갑문을 잘라 갇힌 배를 꺼내던 기술자. 잘라야 할 것은 적과 생존자 사이의 장애물뿐이라고 말한다.", "color": "#1DC8E5", "h": 116, "sc": 1.00, "muz": [0.6556, -0.6755], "wind": 0.833, "art": "res://art/units/glaukos.png", "anim": "res://art/anim/glaukos/"},
	{"id": "volcan", "ko": "볼칸", "en": "Volcan", "tier": 4, "role": "area", "profile": "heavy", "bullet": "zone", "weapon": "deck", "elem": "fire", "desc": "땅을 치면 균열이 달려간다", "lore": "지하 난방관을 놓던 공사 책임자. 붕괴된 지하도에 공기를 넣기 위해 처음으로 땅을 공격했다.", "color": "#FF6A1A", "h": 116, "sc": 1.00, "muz": [0.2789, -0.6211], "wind": 0.667, "art": "res://art/units/volcan.png", "anim": "res://art/anim/volcan/"},
	{"id": "eira", "ko": "에이라", "en": "Eira", "tier": 4, "role": "ricochet", "profile": "sniper", "bullet": "shot", "weapon": "bow", "elem": "ice", "desc": "명중 자리에 작은 눈보라가 남는다", "lore": "설원에서 실종자의 발자국을 찾던 추적자. 적의 발도 눈 위에서 오래 멈추게 만든다.", "color": "#7FD9FF", "h": 116, "sc": 1.00, "muz": [0.3966, -0.6609], "wind": 0.500, "art": "res://art/units/eira.png", "anim": "res://art/anim/eira/"},
	{"id": "conor", "ko": "코너", "en": "Conor", "tier": 4, "role": "single", "profile": "rapid", "bullet": "shot", "weapon": "gun", "elem": "elec", "desc": "같은 놈을 다섯 번 맞히면 터진다", "lore": "전차 배터리를 검사하던 순회 기사. 숫자를 끝까지 확인한 뒤에야 괜찮다고 말하는 성격이다.", "color": "#C8FF2E", "h": 116, "sc": 1.00, "muz": [0.3436, -0.8205], "wind": 0.417, "art": "res://art/units/conor.png", "anim": "res://art/anim/conor/"},
	{"id": "shift", "ko": "시프트", "en": "Shift", "tier": 4, "role": "rider", "profile": "rapid", "bullet": "ricochet", "weapon": "whip", "elem": "none", "desc": "파동이 목표 뒤에서 나타난다", "lore": "좁은 잔해 틈의 철근을 잘라 구조하던 절단사. 정면에서 닿지 않는 곳에도 도구가 돌아 들어갈 길을 찾는다.", "color": "#D93BF0", "h": 116, "sc": 1.00, "muz": [0.6579, -0.7303], "wind": 0.500, "art": "res://art/units/shift.png", "anim": "res://art/anim/shift/"},
	# --- 플러시 ---
	{"id": "thalassa", "ko": "탈라사", "en": "Thalassa", "tier": 5, "role": "area", "profile": "balance", "bullet": "zone", "weapon": "deck", "elem": "water", "desc": "카드가 비가 되어 넓게 내린다", "lore": "화재 때 도시의 빗물 저장소를 개방했던 수리기사. 물을 아끼라는 명령보다 사람을 살리라는 부탁을 택했다.", "color": "#1D9BF0", "h": 121, "sc": 1.00, "muz": [0.1012, -0.6190], "wind": 0.583, "art": "res://art/units/thalassa.png", "anim": "res://art/anim/thalassa/"},
	{"id": "carmen", "ko": "카르멘", "en": "Carmen", "tier": 5, "role": "single", "profile": "rapid", "bullet": "shot", "weapon": "gun", "elem": "fire", "desc": "쌍권총 속사, 카드가 탄피처럼 흩날린다", "lore": "피난 행렬의 옆길을 혼자 막던 호위대원. 사람들이 발걸음을 멈추지 않도록 총성을 일정하게 맞춘다.", "color": "#F0291D", "h": 121, "sc": 1.00, "muz": [0.4140, -0.7962], "wind": 0.583, "art": "res://art/units/carmen.png", "anim": "res://art/anim/carmen/"},
	{"id": "snorri", "ko": "스노리", "en": "Snorri", "tier": 5, "role": "rider", "profile": "balance", "bullet": "splash", "weapon": "whip", "elem": "ice", "desc": "서리 파동이 적을 끌어당긴다", "lore": "얼음에 갇힌 짐과 사람을 함께 끌어올리던 인양공. 무거울수록 웃으며 다른 사람부터 손을 놓게 한다.", "color": "#23E0FF", "h": 121, "sc": 1.00, "muz": [0.6907, -0.6237], "wind": 0.583, "art": "res://art/units/snorri.png", "anim": "res://art/anim/snorri/"},
	{"id": "niamh", "ko": "니브", "en": "Niamh", "tier": 5, "role": "ricochet", "profile": "rapid", "bullet": "chain", "weapon": "bow", "elem": "elec", "desc": "화살이 가까운 놈으로 두 번 뛴다", "lore": "산봉우리 중계탑을 잇던 통신 궁수. 한 곳이 끊겨도 다음 연결 지점을 즉시 찾아낸다.", "color": "#B6F01D", "h": 121, "sc": 1.00, "muz": [0.3145, -0.7419], "wind": 0.500, "art": "res://art/units/niamh.png", "anim": "res://art/anim/niamh/"},
	{"id": "phantom", "ko": "팬텀", "en": "Phantom", "tier": 5, "role": "single", "profile": "sniper", "bullet": "pierce", "weapon": "sword", "elem": "none", "desc": "무형 참격이 방어를 무시한다", "lore": "높은 철골 위에서 잔해를 해체하던 기사. 허공에 남는 두 번째 궤적 때문에 사람들이 유령이라고 불렀다.", "color": "#F03BC0", "h": 121, "sc": 1.00, "muz": [0.5704, -0.6338], "wind": 0.667, "art": "res://art/units/phantom.png", "anim": "res://art/anim/phantom/"},
	# --- 풀하우스 ---
	{"id": "triton", "ko": "트리톤", "en": "Triton", "tier": 6, "role": "single", "profile": "sniper", "bullet": "pierce", "weapon": "gun", "elem": "water", "desc": "발사음 자체가 충격파로 뚫는다", "lore": "입항 신호를 담당했던 포수. 지금도 세 번째 발사 뒤에는 살아 있는 배가 듣기를 바라며 경적을 울린다.", "color": "#1D55F0", "h": 126, "sc": 1.00, "muz": [0.3417, -0.6080], "wind": 0.417, "art": "res://art/units/triton.png", "anim": "res://art/anim/triton/"},
	{"id": "saeta", "ko": "사에타", "en": "Saeta", "tier": 6, "role": "ricochet", "profile": "sniper", "bullet": "splash", "weapon": "bow", "elem": "fire", "desc": "곡사 화살이 떨어진 자리를 태운다", "lore": "산간 역에서 밤하늘에 구조 좌표를 올리던 관측관. 밝은 궤적을 보면 아직 구조를 기다리는 사람이 있다는 뜻이다.", "color": "#FF9226", "h": 126, "sc": 1.00, "muz": [0.4136, -0.7469], "wind": 0.500, "art": "res://art/units/saeta.png", "anim": "res://art/anim/saeta/"},
	{"id": "helga", "ko": "헬가", "en": "Helga", "tier": 6, "role": "single", "profile": "balance", "bullet": "splash", "weapon": "sword", "elem": "ice", "desc": "X자 참격이 교차점에서 터진다", "lore": "빙벽 사이 좁은 통로를 맡았던 방패대장. 두 손으로 길의 양쪽을 막는 기술을 검으로 이어 받았다.", "color": "#5CE8FF", "h": 126, "sc": 1.00, "muz": [0.6303, -0.7273], "wind": 0.500, "art": "res://art/units/helga.png", "anim": "res://art/anim/helga/"},
	{"id": "morrigan", "ko": "모리안", "en": "Morrigan", "tier": 6, "role": "rider", "profile": "rapid", "bullet": "chain", "weapon": "whip", "elem": "elec", "desc": "머리 위로 돌려 방전 필드를 편다", "lore": "야간 송전탑의 순찰 책임자. 피난소 주변에 아무도 뚫고 지나가지 못할 전기 울타리를 세운다.", "color": "#9B5CFF", "h": 126, "sc": 1.00, "muz": [0.5568, -0.6591], "wind": 0.500, "art": "res://art/units/morrigan.png", "anim": "res://art/anim/morrigan/"},
	{"id": "blank", "ko": "블랭크", "en": "Blank", "tier": 6, "role": "area", "profile": "balance", "bullet": "zone", "weapon": "deck", "elem": "none", "desc": "떨어진 자리의 속성을 복사해 터진다", "lore": "피난소에 칸막이를 세우던 방벽 설계자. 빈 판이라고 불린 장비가 가장 많은 사람의 이름을 지켜 냈다.", "color": "#E84FE0", "h": 126, "sc": 1.00, "muz": [0.0990, -0.6198], "wind": 0.500, "art": "res://art/units/blank.png", "anim": "res://art/anim/blank/"},
	# --- 포카드 ---
	{"id": "keto", "ko": "케토", "en": "Keto", "tier": 7, "role": "ricochet", "profile": "balance", "bullet": "pierce", "weapon": "bow", "elem": "water", "desc": "관통한 뒤 뒤쪽으로 튄다", "lore": "심해 관측소 구조 임무에서 돌아온 잠수대장. 두꺼운 외피 뒤에 숨어 있는 목표까지 찾아낸다.", "color": "#1CE5C0", "h": 131, "sc": 1.00, "muz": [0.4528, -0.7170], "wind": 0.500, "art": "res://art/units/keto.png", "anim": "res://art/anim/keto/"},
	{"id": "candela", "ko": "칸델라", "en": "Candela", "tier": 7, "role": "rider", "profile": "balance", "bullet": "splash", "weapon": "whip", "elem": "fire", "desc": "불채찍이 제 둘레를 한 바퀴 돈다", "lore": "성당 급식소 화덕을 지키던 수도사. 자신을 중심으로 안전한 원을 만들고 사람들을 그 안으로 부른다.", "color": "#E5231C", "h": 131, "sc": 1.00, "muz": [0.7097, -0.7097], "wind": 0.667, "art": "res://art/units/candela.png", "anim": "res://art/anim/candela/"},
	{"id": "sigrid", "ko": "시그리드", "en": "Sigrid", "tier": 7, "role": "area", "profile": "sniper", "bullet": "zone", "weapon": "deck", "elem": "ice", "desc": "눈보라 필드가 끝나며 파편으로 터진다", "lore": "붕괴한 냉각탑의 바람길을 다시 설계한 공학자. 사람이 숨 쉴 공간만큼은 얼리지 않도록 제어한다.", "color": "#7FD9FF", "h": 131, "sc": 1.00, "muz": [0.0990, -0.6198], "wind": 0.583, "art": "res://art/units/sigrid.png", "anim": "res://art/anim/sigrid/"},
	{"id": "caden", "ko": "케이든", "en": "Caden", "tier": 7, "role": "single", "profile": "rapid", "bullet": "chain", "weapon": "sword", "elem": "elec", "desc": "삼타째가 인접 둘에게 튄다", "lore": "정전 중 멈춘 승강기를 재시동한 기동대장. 세 단계를 생략하지 않는 습관 덕에 무모한 돌격에서도 살아 돌아왔다.", "color": "#C8FF2E", "h": 131, "sc": 1.00, "muz": [0.7222, -0.5764], "wind": 0.667, "art": "res://art/units/caden.png", "anim": "res://art/anim/caden/"},
	{"id": "grey", "ko": "그레이", "en": "Grey", "tier": 7, "role": "single", "profile": "sniper", "bullet": "shot", "weapon": "gun", "elem": "none", "desc": "치명타 확률이 가장 높다", "lore": "금고 잠금 장치를 검사하던 정밀 기술자. 평범한 한 발에 필요한 준비를 남들보다 오래 한다.", "color": "#FF5CE0", "h": 131, "sc": 1.00, "muz": [0.5208, -0.6979], "wind": 0.417, "art": "res://art/units/grey.png", "anim": "res://art/anim/grey/"},
	# --- 스트레이트플러시 ---
	{"id": "galene", "ko": "갈레네", "en": "Galene", "tier": 8, "role": "rider", "profile": "heavy", "bullet": "splash", "weapon": "whip", "elem": "water", "desc": "한 번만 휘둘러 젖음을 세 겹 남긴다", "lore": "폭풍 속에서도 대피선의 항로를 유지한 조류 제어사. 장비가 힘을 만들기 때문에 사람은 작고 정확하게 움직인다.", "color": "#1D9BF0", "h": 136, "sc": 1.00, "muz": [0.4112, -0.7310], "wind": 0.583, "art": "res://art/units/galene.png", "anim": "res://art/anim/galene/"},
	{"id": "estoque", "ko": "에스토크", "en": "Estoque", "tier": 8, "role": "single", "profile": "sniper", "bullet": "pierce", "weapon": "sword", "elem": "fire", "desc": "직선 화염 찌르기가 줄지어 뚫는다", "lore": "두꺼운 피난문을 최소한의 절단면으로 열던 공병 기사. 큰 불로 주변까지 태우지 않고 필요한 한 점만 녹인다.", "color": "#F0451D", "h": 136, "sc": 1.00, "muz": [0.7721, -0.6691], "wind": 0.583, "art": "res://art/units/estoque.png", "anim": "res://art/anim/estoque/"},
	{"id": "frosti", "ko": "프로스티", "en": "Frosti", "tier": 8, "role": "single", "profile": "sniper", "bullet": "beam", "weapon": "gun", "elem": "ice", "desc": "단발 저격이 대상을 완전히 멈춘다", "lore": "혹한 관측소에서 구조 로프 끝만 정확히 맞히던 명사수. 움직임이 멈추는 순간을 오래 기다릴 줄 안다.", "color": "#23E0FF", "h": 136, "sc": 1.00, "muz": [0.6026, -0.7152], "wind": 0.417, "art": "res://art/units/frosti.png", "anim": "res://art/anim/frosti/"},
	{"id": "lugh", "ko": "루흐", "en": "Lugh", "tier": 8, "role": "area", "profile": "sniper", "bullet": "zone", "weapon": "deck", "elem": "elec", "desc": "뇌운이 넓게 퍼져 연달아 내리친다", "lore": "도시 전력망을 끝까지 나누어 공급한 총괄 기사. 한 사람이 모든 빛을 독차지하지 않도록 설계했던 힘이다.", "color": "#D6F01D", "h": 136, "sc": 1.00, "muz": [0.0979, -0.6186], "wind": 0.500, "art": "res://art/units/lugh.png", "anim": "res://art/anim/lugh/"},
	{"id": "null", "ko": "널", "en": "Null", "tier": 8, "role": "ricochet", "profile": "sniper", "bullet": "pierce", "weapon": "bow", "elem": "none", "desc": "존재하지 않는 화살이 저항을 무시한다", "lore": "두꺼운 금고 벽에 가장 작은 구멍을 내던 장인. 부수지 않고 통과하는 방법을 찾던 기록이 남아 있다.", "color": "#B84FFF", "h": 136, "sc": 1.00, "muz": [0.4106, -0.6424], "wind": 0.500, "art": "res://art/units/null.png", "anim": "res://art/anim/null/"},
	# --- 로열플러시 ---
	{"id": "nerea", "ko": "네레아", "en": "Nerea", "tier": 9, "role": "single", "profile": "heavy", "bullet": "pierce", "weapon": "sword", "elem": "water", "desc": "물기둥 참격이 세 번마다 세 갈래로 갈라진다", "lore": "첫 홍수 때 몸으로 갑문을 지킨 방어망 창설자. 이름이 전설이 된 뒤에도 스스로를 문지기라고 소개한다.", "color": "#1D55F0", "h": 141, "sc": 1.00, "muz": [0.6250, -0.6131], "wind": 0.750, "art": "res://art/units/nerea.png", "anim": "res://art/anim/nerea/"},
	{"id": "brasa", "ko": "브라사", "en": "Brasa", "tier": 9, "role": "area", "profile": "heavy", "bullet": "zone", "weapon": "deck", "elem": "fire", "desc": "올인 한 번에 불바다가 깔린다", "lore": "첫 대피소의 보일러를 지키던 수석 기관사. 강력한 수호자의 기록에도 사람을 데우던 본래 목적이 남아 있다.", "color": "#FF6A1A", "h": 141, "sc": 1.00, "muz": [0.1010, -0.6212], "wind": 0.583, "art": "res://art/units/brasa.png", "anim": "res://art/anim/brasa/"},
	{"id": "isa", "ko": "이사", "en": "Isa", "tier": 9, "role": "ricochet", "profile": "heavy", "bullet": "pierce", "weapon": "bow", "elem": "ice", "desc": "풀차지 고드름이 길을 막는다", "lore": "마지막 산악 대피로의 빙문을 세운 수호장. 길을 봉쇄하는 힘으로 사람에게 열어 줄 시간을 만든다.", "color": "#5CE8FF", "h": 141, "sc": 1.00, "muz": [0.3285, -0.7007], "wind": 0.500, "art": "res://art/units/isa.png", "anim": "res://art/anim/isa/"},
	{"id": "brian", "ko": "브리안", "en": "Brian", "tier": 9, "role": "single", "profile": "heavy", "bullet": "beam", "weapon": "gun", "elem": "elec", "desc": "레일건 뇌격이 줄지어 꿰뚫는다", "lore": "주 전력선이 끊기자 자기 장비를 임시 송전선으로 쓴 수석 기사. 남은 한 번의 전류도 허투루 쏘지 않는다.", "color": "#9B5CFF", "h": 141, "sc": 1.00, "muz": [0.3750, -0.6927], "wind": 0.500, "art": "res://art/units/brian.png", "anim": "res://art/anim/brian/"},
	{"id": "zero", "ko": "제로", "en": "Zero", "tier": 9, "role": "rider", "profile": "sniper", "bullet": "splash", "weapon": "whip", "elem": "none", "desc": "무색 파동이 옆 아군의 속성을 흉내 낸다", "lore": "서로 다른 도시 설비를 한 방어망으로 이은 창설자. 혼자 가장 강한 것보다 함께 작동하는 것을 완성품이라고 여긴다.", "color": "#FF4FD8", "h": 141, "sc": 1.00, "muz": [0.4315, -0.6091], "wind": 0.583, "art": "res://art/units/zero.png", "anim": "res://art/anim/zero/"},
]

## 몬스터 25종. body 는 **몸 속성** 다섯 가지 중 하나다(Balance.MBODY) —
## aqua 물 · flame 불 · wood 나무 · rock 바위 · frost 얼음.
## ★ 몸 다섯 × 형 넷 = 스무 종에 보스 다섯이다. 형(kind)이 체력·속도를 정하고
##   몸(body)이 상성을 정한다 — 둘은 서로 아무 상관이 없는 축이다.
const MONSTERS := [
	{"id": "drop_slime", "ko": "물방울슬라임", "kind": "swarm", "body": "aqua", "desc": "탁한 물이 굴러온다", "color": "#3FC8FF", "h": 52, "art": "res://art/monsters/drop_slime.png", "anim": "res://art/anim/monsters/drop_slime/"},
	{"id": "rapid_ray", "ko": "격류가오리", "kind": "fast", "body": "aqua", "desc": "검은 물살을 가른다", "color": "#00C8C0", "h": 48, "art": "res://art/monsters/rapid_ray.png", "anim": "res://art/anim/monsters/rapid_ray/"},
	{"id": "wave_giant", "ko": "파도거인", "kind": "tank", "body": "aqua", "desc": "밤바다가 걸어온다", "color": "#2E86FF", "h": 68, "art": "res://art/monsters/wave_giant.png", "anim": "res://art/anim/monsters/wave_giant/"},
	{"id": "jelly_seer", "ko": "해파리술사", "kind": "caster", "body": "aqua", "desc": "촉수로 저주를 흘린다", "color": "#9C7BFF", "h": 58, "art": "res://art/monsters/jelly_seer.png", "anim": "res://art/anim/monsters/jelly_seer/"},
	{"id": "ember_imp", "ko": "불씨꼬마", "kind": "swarm", "body": "flame", "desc": "재 속의 잔불 떼", "color": "#FFC24A", "h": 52, "art": "res://art/monsters/ember_imp.png", "anim": "res://art/anim/monsters/ember_imp/"},
	{"id": "blaze_fox", "ko": "불꽃여우", "kind": "fast", "body": "flame", "desc": "그을린 꼬리를 끈다", "color": "#FF7A2E", "h": 48, "art": "res://art/monsters/blaze_fox.png", "anim": "res://art/anim/monsters/blaze_fox/"},
	{"id": "magma_brute", "ko": "용암괴수", "kind": "tank", "body": "flame", "desc": "갈라진 틈이 벌겋다", "color": "#E8401A", "h": 68, "art": "res://art/monsters/magma_brute.png", "anim": "res://art/anim/monsters/magma_brute/"},
	{"id": "pyre_priest", "ko": "화염사제", "kind": "caster", "body": "flame", "desc": "잿불을 던져 온다", "color": "#FF6B4A", "h": 58, "art": "res://art/monsters/pyre_priest.png", "anim": "res://art/anim/monsters/pyre_priest/"},
	{"id": "bramble_imp", "ko": "덤불꼬마", "kind": "swarm", "body": "wood", "desc": "가시덤불이 몰려온다", "color": "#6FD44F", "h": 52, "art": "res://art/monsters/bramble_imp.png", "anim": "res://art/anim/monsters/bramble_imp/"},
	{"id": "vine_lynx", "ko": "덩굴표범", "kind": "fast", "body": "wood", "desc": "덩굴을 타고 달려든다", "color": "#A6E03C", "h": 48, "art": "res://art/monsters/vine_lynx.png", "anim": "res://art/anim/monsters/vine_lynx/"},
	{"id": "elder_treant", "ko": "고목거인", "kind": "tank", "body": "wood", "desc": "이끼 낀 늙은 나무", "color": "#5FA83C", "h": 68, "art": "res://art/monsters/elder_treant.png", "anim": "res://art/anim/monsters/elder_treant/"},
	{"id": "spore_cap", "ko": "포자버섯", "kind": "caster", "body": "wood", "desc": "포자를 흩뿌린다", "color": "#FF5C7A", "h": 58, "art": "res://art/monsters/spore_cap.png", "anim": "res://art/anim/monsters/spore_cap/"},
	{"id": "pebble_imp", "ko": "자갈꼬마", "kind": "swarm", "body": "rock", "desc": "돌멩이가 떼로 굴러온다", "color": "#A9B2B8", "h": 52, "art": "res://art/monsters/pebble_imp.png", "anim": "res://art/anim/monsters/pebble_imp/"},
	{"id": "crystal_skink", "ko": "수정도마뱀", "kind": "fast", "body": "rock", "desc": "수정 비늘로 재빠르다", "color": "#F2B33A", "h": 48, "art": "res://art/monsters/crystal_skink.png", "anim": "res://art/anim/monsters/crystal_skink/"},
	{"id": "stone_golem", "ko": "돌골렘", "kind": "tank", "body": "rock", "desc": "느리지만 아주 튼튼하다", "color": "#C89B5A", "h": 68, "art": "res://art/monsters/stone_golem.png", "anim": "res://art/anim/monsters/stone_golem/"},
	{"id": "runestone_idol", "ko": "석상술사", "kind": "caster", "body": "rock", "desc": "돌기둥이 저주를 쏜다", "color": "#BFD0DC", "h": 58, "art": "res://art/monsters/runestone_idol.png", "anim": "res://art/anim/monsters/runestone_idol/"},
	{"id": "frost_imp", "ko": "서리꼬마", "kind": "swarm", "body": "frost", "desc": "언 눈덩이가 굴러온다", "color": "#B7F0FF", "h": 52, "art": "res://art/monsters/frost_imp.png", "anim": "res://art/anim/monsters/frost_imp/"},
	{"id": "blizzard_wolf", "ko": "눈보라늑대", "kind": "fast", "body": "frost", "desc": "눈보라처럼 파고든다", "color": "#C3CCFF", "h": 48, "art": "res://art/monsters/blizzard_wolf.png", "anim": "res://art/anim/monsters/blizzard_wolf/"},
	{"id": "glacier_titan", "ko": "빙하거인", "kind": "tank", "body": "frost", "desc": "잿빛 얼음의 거인", "color": "#74DAF2", "h": 68, "art": "res://art/monsters/glacier_titan.png", "anim": "res://art/anim/monsters/glacier_titan/"},
	{"id": "rime_witch", "ko": "얼음마녀", "kind": "caster", "body": "frost", "desc": "얼음 저주를 날린다", "color": "#8A9CFF", "h": 58, "art": "res://art/monsters/rime_witch.png", "anim": "res://art/anim/monsters/rime_witch/"},
	{"id": "abyss_leviathan", "ko": "심연해룡", "kind": "boss", "body": "aqua", "desc": "심연에서 올라온 거수", "color": "#1F63E8", "h": 132, "art": "res://art/monsters/abyss_leviathan.png", "anim": "res://art/anim/monsters/abyss_leviathan/"},
	{"id": "flame_dragon", "ko": "화염용", "kind": "boss", "body": "flame", "desc": "불을 뿜는 거대한 용", "color": "#FF5A16", "h": 132, "art": "res://art/monsters/flame_dragon.png", "anim": "res://art/anim/monsters/flame_dragon/"},
	{"id": "titan_bloom", "ko": "식인꽃왕", "kind": "boss", "body": "wood", "desc": "아가리를 벌린 거대 꽃", "color": "#E64BD8", "h": 132, "art": "res://art/monsters/titan_bloom.png", "anim": "res://art/anim/monsters/titan_bloom/"},
	{"id": "crystal_golem_king", "ko": "수정골렘왕", "kind": "boss", "body": "rock", "desc": "산더미 같은 수정 거인", "color": "#B056F5", "h": 132, "art": "res://art/monsters/crystal_golem_king.png", "anim": "res://art/anim/monsters/crystal_golem_king/"},
	{"id": "glacier_dragon", "ko": "빙하용왕", "kind": "boss", "body": "frost", "desc": "얼어붙은 거대한 용", "color": "#59BFF0", "h": 132, "art": "res://art/monsters/glacier_dragon.png", "anim": "res://art/anim/monsters/glacier_dragon/"},
]

## 테마 50개. **열 탄이 한 테마**이고 그 열 번째 탄이 보스맵이다.
##
## weights 는 다섯 몸의 등장 확률이고 합이 1.0 이다. 「호수면 물 몬스터가 많이 나온다」가
## 주 속성은 70~80%, 나머지는 테마의 보조 속성 비율이다. 보스는 항상 주 속성이다.
## theme_spawns가 실제 개체 수로 배분하며, 첫 테마는 초반 면역 보호와 맞춰 선택한다.
##
## rank(1~5)는 그곳이 얼마나 험한가다. 체력에 곱해지고(Balance.theme_hp), 뒤 블록일수록
## 높은 rank 가 걸린다(Run.roll_themes). 사용자가 정한 「뒤로 갈수록 세진다」가 이것이다.
const THEMES := [
	{"id": "calm_lake", "ko": "잔잔한 호수", "main_body": "aqua", "boss_body": "aqua", "rank": 1, "weights": {"aqua": 0.70, "flame": 0.06, "wood": 0.12, "rock": 0.06, "frost": 0.06}, "bg": "#10243A", "floor": "#1B3A4A", "art_bg": "res://art/themes/calm_lake_bg.png", "art_floor": "res://art/themes/calm_lake_floor.png"},
	{"id": "reed_marsh", "ko": "갈대 늪", "main_body": "aqua", "boss_body": "aqua", "rank": 1, "weights": {"aqua": 0.70, "flame": 0.06, "wood": 0.12, "rock": 0.06, "frost": 0.06}, "bg": "#142A2A", "floor": "#22362C", "art_bg": "res://art/themes/reed_marsh_bg.png", "art_floor": "res://art/themes/reed_marsh_floor.png"},
	{"id": "aqueduct_ruin", "ko": "수도교 폐허", "main_body": "aqua", "boss_body": "aqua", "rank": 2, "weights": {"aqua": 0.72, "flame": 0.05, "wood": 0.06, "rock": 0.12, "frost": 0.05}, "bg": "#1A2233", "floor": "#2A3038", "art_bg": "res://art/themes/aqueduct_ruin_bg.png", "art_floor": "res://art/themes/aqueduct_ruin_floor.png"},
	{"id": "falls_gorge", "ko": "폭포 골짜기", "main_body": "aqua", "boss_body": "aqua", "rank": 2, "weights": {"aqua": 0.72, "flame": 0.05, "wood": 0.06, "rock": 0.12, "frost": 0.05}, "bg": "#0E2833", "floor": "#1D3540", "art_bg": "res://art/themes/falls_gorge_bg.png", "art_floor": "res://art/themes/falls_gorge_floor.png"},
	{"id": "tidal_flats", "ko": "밀물 갯벌", "main_body": "aqua", "boss_body": "aqua", "rank": 3, "weights": {"aqua": 0.75, "flame": 0.05, "wood": 0.06, "rock": 0.10, "frost": 0.04}, "bg": "#17293A", "floor": "#2A3340", "art_bg": "res://art/themes/tidal_flats_bg.png", "art_floor": "res://art/themes/tidal_flats_floor.png"},
	{"id": "glacier_lake", "ko": "빙하호", "main_body": "aqua", "boss_body": "aqua", "rank": 3, "weights": {"aqua": 0.75, "flame": 0.04, "wood": 0.06, "rock": 0.05, "frost": 0.10}, "bg": "#102A3E", "floor": "#1E3A4C", "art_bg": "res://art/themes/glacier_lake_bg.png", "art_floor": "res://art/themes/glacier_lake_floor.png"},
	{"id": "sunken_fleet", "ko": "침몰선 무덤", "main_body": "aqua", "boss_body": "aqua", "rank": 4, "weights": {"aqua": 0.78, "flame": 0.07, "wood": 0.04, "rock": 0.07, "frost": 0.04}, "bg": "#0B1F2E", "floor": "#17303A", "art_bg": "res://art/themes/sunken_fleet_bg.png", "art_floor": "res://art/themes/sunken_fleet_floor.png"},
	{"id": "geyser_mud", "ko": "간헐천 진흙벌", "main_body": "aqua", "boss_body": "aqua", "rank": 4, "weights": {"aqua": 0.78, "flame": 0.10, "wood": 0.04, "rock": 0.04, "frost": 0.04}, "bg": "#1E2429", "floor": "#2E2A22", "art_bg": "res://art/themes/geyser_mud_bg.png", "art_floor": "res://art/themes/geyser_mud_floor.png"},
	{"id": "deep_trench", "ko": "심해 해구", "main_body": "aqua", "boss_body": "aqua", "rank": 5, "weights": {"aqua": 0.80, "flame": 0.07, "wood": 0.03, "rock": 0.06, "frost": 0.04}, "bg": "#060F1C", "floor": "#0E1E2A", "art_bg": "res://art/themes/deep_trench_bg.png", "art_floor": "res://art/themes/deep_trench_floor.png"},
	{"id": "maelstrom_sea", "ko": "소용돌이 바다", "main_body": "aqua", "boss_body": "aqua", "rank": 5, "weights": {"aqua": 0.80, "flame": 0.03, "wood": 0.07, "rock": 0.04, "frost": 0.06}, "bg": "#0A1826", "floor": "#142A38", "art_bg": "res://art/themes/maelstrom_sea_bg.png", "art_floor": "res://art/themes/maelstrom_sea_floor.png"},
	{"id": "kiln_yard", "ko": "가마터", "main_body": "flame", "boss_body": "flame", "rank": 1, "weights": {"aqua": 0.06, "flame": 0.70, "wood": 0.06, "rock": 0.13, "frost": 0.05}, "bg": "#241A16", "floor": "#33251C", "art_bg": "res://art/themes/kiln_yard_bg.png", "art_floor": "res://art/themes/kiln_yard_floor.png"},
	{"id": "burn_field", "ko": "화전 들판", "main_body": "flame", "boss_body": "flame", "rank": 1, "weights": {"aqua": 0.06, "flame": 0.70, "wood": 0.12, "rock": 0.06, "frost": 0.06}, "bg": "#2A1E14", "floor": "#33291F", "art_bg": "res://art/themes/burn_field_bg.png", "art_floor": "res://art/themes/burn_field_floor.png"},
	{"id": "forge_canyon", "ko": "대장간 골", "main_body": "flame", "boss_body": "flame", "rank": 2, "weights": {"aqua": 0.05, "flame": 0.72, "wood": 0.06, "rock": 0.12, "frost": 0.05}, "bg": "#1E1310", "floor": "#2E1E17", "art_bg": "res://art/themes/forge_canyon_bg.png", "art_floor": "res://art/themes/forge_canyon_floor.png"},
	{"id": "burnt_forest", "ko": "불탄 숲", "main_body": "flame", "boss_body": "flame", "rank": 2, "weights": {"aqua": 0.05, "flame": 0.72, "wood": 0.12, "rock": 0.06, "frost": 0.05}, "bg": "#201A18", "floor": "#2B2320", "art_bg": "res://art/themes/burnt_forest_bg.png", "art_floor": "res://art/themes/burnt_forest_floor.png"},
	{"id": "sulfur_springs", "ko": "유황 온천", "main_body": "flame", "boss_body": "flame", "rank": 3, "weights": {"aqua": 0.10, "flame": 0.75, "wood": 0.05, "rock": 0.05, "frost": 0.05}, "bg": "#2A2412", "floor": "#35301A", "art_bg": "res://art/themes/sulfur_springs_bg.png", "art_floor": "res://art/themes/sulfur_springs_floor.png"},
	{"id": "ash_city", "ko": "잿빛 폐허", "main_body": "flame", "boss_body": "flame", "rank": 3, "weights": {"aqua": 0.04, "flame": 0.75, "wood": 0.07, "rock": 0.10, "frost": 0.04}, "bg": "#221D1C", "floor": "#2C2726", "art_bg": "res://art/themes/ash_city_bg.png", "art_floor": "res://art/themes/ash_city_floor.png"},
	{"id": "lava_river", "ko": "용암 강", "main_body": "flame", "boss_body": "flame", "rank": 4, "weights": {"aqua": 0.02, "flame": 0.78, "wood": 0.07, "rock": 0.08, "frost": 0.05}, "bg": "#1A0D0A", "floor": "#2B120C", "art_bg": "res://art/themes/lava_river_bg.png", "art_floor": "res://art/themes/lava_river_floor.png"},
	{"id": "obsidian_flats", "ko": "흑요석 벌", "main_body": "flame", "boss_body": "flame", "rank": 4, "weights": {"aqua": 0.09, "flame": 0.78, "wood": 0.04, "rock": 0.05, "frost": 0.04}, "bg": "#14100F", "floor": "#1C1A1D", "art_bg": "res://art/themes/obsidian_flats_bg.png", "art_floor": "res://art/themes/obsidian_flats_floor.png"},
	{"id": "volcano_crater", "ko": "활화산 분화구", "main_body": "flame", "boss_body": "flame", "rank": 5, "weights": {"aqua": 0.02, "flame": 0.80, "wood": 0.07, "rock": 0.07, "frost": 0.04}, "bg": "#180A08", "floor": "#2A100A", "art_bg": "res://art/themes/volcano_crater_bg.png", "art_floor": "res://art/themes/volcano_crater_floor.png"},
	{"id": "ash_blizzard", "ko": "잿눈 화산", "main_body": "flame", "boss_body": "flame", "rank": 5, "weights": {"aqua": 0.08, "flame": 0.80, "wood": 0.03, "rock": 0.02, "frost": 0.07}, "bg": "#1C1A1E", "floor": "#2A2426", "art_bg": "res://art/themes/ash_blizzard_bg.png", "art_floor": "res://art/themes/ash_blizzard_floor.png"},
	{"id": "spring_grove", "ko": "봄 숲", "main_body": "wood", "boss_body": "wood", "rank": 1, "weights": {"aqua": 0.14, "flame": 0.05, "wood": 0.70, "rock": 0.05, "frost": 0.06}, "bg": "#16281B", "floor": "#24371F", "art_bg": "res://art/themes/spring_grove_bg.png", "art_floor": "res://art/themes/spring_grove_floor.png"},
	{"id": "mushroom_hollow", "ko": "버섯 골짜기", "main_body": "wood", "boss_body": "wood", "rank": 1, "weights": {"aqua": 0.14, "flame": 0.06, "wood": 0.70, "rock": 0.04, "frost": 0.06}, "bg": "#17201F", "floor": "#26302A", "art_bg": "res://art/themes/mushroom_hollow_bg.png", "art_floor": "res://art/themes/mushroom_hollow_floor.png"},
	{"id": "bamboo_grove", "ko": "대숲", "main_body": "wood", "boss_body": "wood", "rank": 2, "weights": {"aqua": 0.15, "flame": 0.05, "wood": 0.72, "rock": 0.03, "frost": 0.05}, "bg": "#13251C", "floor": "#203122", "art_bg": "res://art/themes/bamboo_grove_bg.png", "art_floor": "res://art/themes/bamboo_grove_floor.png"},
	{"id": "vine_ruins", "ko": "덩굴 폐허", "main_body": "wood", "boss_body": "wood", "rank": 2, "weights": {"aqua": 0.16, "flame": 0.05, "wood": 0.72, "rock": 0.02, "frost": 0.05}, "bg": "#1A2419", "floor": "#283026", "art_bg": "res://art/themes/vine_ruins_bg.png", "art_floor": "res://art/themes/vine_ruins_floor.png"},
	{"id": "misty_cedar", "ko": "안개 삼나무", "main_body": "wood", "boss_body": "wood", "rank": 3, "weights": {"aqua": 0.14, "flame": 0.05, "wood": 0.75, "rock": 0.02, "frost": 0.04}, "bg": "#16221F", "floor": "#223028", "art_bg": "res://art/themes/misty_cedar_bg.png", "art_floor": "res://art/themes/misty_cedar_floor.png"},
	{"id": "thornbrake", "ko": "가시덤불", "main_body": "wood", "boss_body": "wood", "rank": 3, "weights": {"aqua": 0.04, "flame": 0.15, "wood": 0.75, "rock": 0.02, "frost": 0.04}, "bg": "#221F14", "floor": "#2E2A1B", "art_bg": "res://art/themes/thornbrake_bg.png", "art_floor": "res://art/themes/thornbrake_floor.png"},
	{"id": "moss_bog", "ko": "이끼 습지", "main_body": "wood", "boss_body": "wood", "rank": 4, "weights": {"aqua": 0.12, "flame": 0.04, "wood": 0.78, "rock": 0.02, "frost": 0.04}, "bg": "#12201A", "floor": "#1E2C20", "art_bg": "res://art/themes/moss_bog_bg.png", "art_floor": "res://art/themes/moss_bog_floor.png"},
	{"id": "frost_pines", "ko": "서리 침엽수", "main_body": "wood", "boss_body": "wood", "rank": 4, "weights": {"aqua": 0.04, "flame": 0.04, "wood": 0.78, "rock": 0.01, "frost": 0.13}, "bg": "#16222A", "floor": "#223029", "art_bg": "res://art/themes/frost_pines_bg.png", "art_floor": "res://art/themes/frost_pines_floor.png"},
	{"id": "rotroot_hollow", "ko": "썩은 뿌리굴", "main_body": "wood", "boss_body": "wood", "rank": 5, "weights": {"aqua": 0.10, "flame": 0.03, "wood": 0.80, "rock": 0.02, "frost": 0.05}, "bg": "#171A14", "floor": "#23261A", "art_bg": "res://art/themes/rotroot_hollow_bg.png", "art_floor": "res://art/themes/rotroot_hollow_floor.png"},
	{"id": "worldtree_roots", "ko": "세계수 뿌리", "main_body": "wood", "boss_body": "wood", "rank": 5, "weights": {"aqua": 0.12, "flame": 0.03, "wood": 0.80, "rock": 0.02, "frost": 0.03}, "bg": "#131C18", "floor": "#1F2A1E", "art_bg": "res://art/themes/worldtree_roots_bg.png", "art_floor": "res://art/themes/worldtree_roots_floor.png"},
	{"id": "gravel_hills", "ko": "자갈 언덕", "main_body": "rock", "boss_body": "rock", "rank": 1, "weights": {"aqua": 0.06, "flame": 0.06, "wood": 0.07, "rock": 0.70, "frost": 0.11}, "bg": "#24241F", "floor": "#33322A", "art_bg": "res://art/themes/gravel_hills_bg.png", "art_floor": "res://art/themes/gravel_hills_floor.png"},
	{"id": "stone_terraces", "ko": "돌담 밭", "main_body": "rock", "boss_body": "rock", "rank": 1, "weights": {"aqua": 0.11, "flame": 0.06, "wood": 0.07, "rock": 0.70, "frost": 0.06}, "bg": "#222620", "floor": "#30322A", "art_bg": "res://art/themes/stone_terraces_bg.png", "art_floor": "res://art/themes/stone_terraces_floor.png"},
	{"id": "quarry_pit", "ko": "채석장", "main_body": "rock", "boss_body": "rock", "rank": 2, "weights": {"aqua": 0.05, "flame": 0.11, "wood": 0.07, "rock": 0.72, "frost": 0.05}, "bg": "#26241F", "floor": "#34322B", "art_bg": "res://art/themes/quarry_pit_bg.png", "art_floor": "res://art/themes/quarry_pit_floor.png"},
	{"id": "red_canyon", "ko": "붉은 협곡", "main_body": "rock", "boss_body": "rock", "rank": 2, "weights": {"aqua": 0.06, "flame": 0.11, "wood": 0.06, "rock": 0.72, "frost": 0.05}, "bg": "#2A1C16", "floor": "#38251B", "art_bg": "res://art/themes/red_canyon_bg.png", "art_floor": "res://art/themes/red_canyon_floor.png"},
	{"id": "broken_wall", "ko": "무너진 성벽", "main_body": "rock", "boss_body": "rock", "rank": 3, "weights": {"aqua": 0.09, "flame": 0.05, "wood": 0.06, "rock": 0.75, "frost": 0.05}, "bg": "#22242A", "floor": "#2E3036", "art_bg": "res://art/themes/broken_wall_bg.png", "art_floor": "res://art/themes/broken_wall_floor.png"},
	{"id": "crystal_cavern", "ko": "수정 동굴", "main_body": "rock", "boss_body": "rock", "rank": 3, "weights": {"aqua": 0.07, "flame": 0.03, "wood": 0.05, "rock": 0.75, "frost": 0.10}, "bg": "#171C2A", "floor": "#232838", "art_bg": "res://art/themes/crystal_cavern_bg.png", "art_floor": "res://art/themes/crystal_cavern_floor.png"},
	{"id": "desert_mesa", "ko": "사막 바위기둥", "main_body": "rock", "boss_body": "rock", "rank": 4, "weights": {"aqua": 0.06, "flame": 0.07, "wood": 0.05, "rock": 0.78, "frost": 0.04}, "bg": "#2C2318", "floor": "#382C1E", "art_bg": "res://art/themes/desert_mesa_bg.png", "art_floor": "res://art/themes/desert_mesa_floor.png"},
	{"id": "iron_mine", "ko": "철광 갱도", "main_body": "rock", "boss_body": "rock", "rank": 4, "weights": {"aqua": 0.06, "flame": 0.08, "wood": 0.04, "rock": 0.78, "frost": 0.04}, "bg": "#1C1A18", "floor": "#282422", "art_bg": "res://art/themes/iron_mine_bg.png", "art_floor": "res://art/themes/iron_mine_floor.png"},
	{"id": "peak_cliffs", "ko": "산정 절벽", "main_body": "rock", "boss_body": "rock", "rank": 5, "weights": {"aqua": 0.06, "flame": 0.03, "wood": 0.04, "rock": 0.80, "frost": 0.07}, "bg": "#1B222C", "floor": "#272E38", "art_bg": "res://art/themes/peak_cliffs_bg.png", "art_floor": "res://art/themes/peak_cliffs_floor.png"},
	{"id": "rift_chasm", "ko": "지진 균열", "main_body": "rock", "boss_body": "rock", "rank": 5, "weights": {"aqua": 0.06, "flame": 0.06, "wood": 0.04, "rock": 0.80, "frost": 0.04}, "bg": "#1A1512", "floor": "#26201C", "art_bg": "res://art/themes/rift_chasm_bg.png", "art_floor": "res://art/themes/rift_chasm_floor.png"},
	{"id": "first_snow_hills", "ko": "첫눈 언덕", "main_body": "frost", "boss_body": "frost", "rank": 1, "weights": {"aqua": 0.06, "flame": 0.06, "wood": 0.12, "rock": 0.06, "frost": 0.70}, "bg": "#1E2A38", "floor": "#2C3A46", "art_bg": "res://art/themes/first_snow_hills_bg.png", "art_floor": "res://art/themes/first_snow_hills_floor.png"},
	{"id": "frozen_pond", "ko": "얼어붙은 연못", "main_body": "frost", "boss_body": "frost", "rank": 1, "weights": {"aqua": 0.16, "flame": 0.06, "wood": 0.06, "rock": 0.02, "frost": 0.70}, "bg": "#182838", "floor": "#263846", "art_bg": "res://art/themes/frozen_pond_bg.png", "art_floor": "res://art/themes/frozen_pond_floor.png"},
	{"id": "snowed_village", "ko": "눈 덮인 마을터", "main_body": "frost", "boss_body": "frost", "rank": 2, "weights": {"aqua": 0.05, "flame": 0.05, "wood": 0.12, "rock": 0.06, "frost": 0.72}, "bg": "#1E2634", "floor": "#2C3440", "art_bg": "res://art/themes/snowed_village_bg.png", "art_floor": "res://art/themes/snowed_village_floor.png"},
	{"id": "frost_gorge", "ko": "서리 협곡", "main_body": "frost", "boss_body": "frost", "rank": 2, "weights": {"aqua": 0.05, "flame": 0.06, "wood": 0.05, "rock": 0.12, "frost": 0.72}, "bg": "#182430", "floor": "#26323C", "art_bg": "res://art/themes/frost_gorge_bg.png", "art_floor": "res://art/themes/frost_gorge_floor.png"},
	{"id": "drift_ice_sea", "ko": "유빙 바다", "main_body": "frost", "boss_body": "frost", "rank": 3, "weights": {"aqua": 0.04, "flame": 0.10, "wood": 0.05, "rock": 0.06, "frost": 0.75}, "bg": "#12283A", "floor": "#203846", "art_bg": "res://art/themes/drift_ice_sea_bg.png", "art_floor": "res://art/themes/drift_ice_sea_floor.png"},
	{"id": "icicle_cave", "ko": "고드름 동굴", "main_body": "frost", "boss_body": "frost", "rank": 3, "weights": {"aqua": 0.04, "flame": 0.04, "wood": 0.07, "rock": 0.10, "frost": 0.75}, "bg": "#141E2C", "floor": "#202C3A", "art_bg": "res://art/themes/icicle_cave_bg.png", "art_floor": "res://art/themes/icicle_cave_floor.png"},
	{"id": "blizzard_plateau", "ko": "눈보라 고원", "main_body": "frost", "boss_body": "frost", "rank": 4, "weights": {"aqua": 0.02, "flame": 0.07, "wood": 0.05, "rock": 0.08, "frost": 0.78}, "bg": "#1A222E", "floor": "#28303A", "art_bg": "res://art/themes/blizzard_plateau_bg.png", "art_floor": "res://art/themes/blizzard_plateau_floor.png"},
	{"id": "glacier_crevasse", "ko": "빙하 균열", "main_body": "frost", "boss_body": "frost", "rank": 4, "weights": {"aqua": 0.02, "flame": 0.11, "wood": 0.04, "rock": 0.05, "frost": 0.78}, "bg": "#0E2436", "floor": "#1A3244", "art_bg": "res://art/themes/glacier_crevasse_bg.png", "art_floor": "res://art/themes/glacier_crevasse_floor.png"},
	{"id": "ice_spire_field", "ko": "얼음 첨탑 벌", "main_body": "frost", "boss_body": "frost", "rank": 5, "weights": {"aqua": 0.02, "flame": 0.08, "wood": 0.03, "rock": 0.07, "frost": 0.80}, "bg": "#101C2E", "floor": "#1C2A3C", "art_bg": "res://art/themes/ice_spire_field_bg.png", "art_floor": "res://art/themes/ice_spire_field_floor.png"},
	{"id": "polar_night", "ko": "극야 빙원", "main_body": "frost", "boss_body": "frost", "rank": 5, "weights": {"aqua": 0.02, "flame": 0.12, "wood": 0.02, "rock": 0.04, "frost": 0.80}, "bg": "#0A1220", "floor": "#14202E", "art_bg": "res://art/themes/polar_night_bg.png", "art_floor": "res://art/themes/polar_night_floor.png"},
]

## 화면을 채우는 그림들.
const ART := {
	"arena_floor": "res://art/ui/arena_floor.png",
	"arena_bg": "res://art/ui/arena_bg.png",
	"card_back": "res://art/ui/card_back.png",
	"title_art": "res://art/ui/title_allin_courtyard.png",
	"coin": "res://art/ui/coin.png",
	"heart": "res://art/ui/heart.png",
	"shop_bg": "res://art/ui/shop_bg.png",
	"boom": "res://art/ui/boom.png",
	"crystal": "res://art/ui/crystal.png",
	"fx_fire": "res://art/ui/fx_fire.png",
	"fx_ice_bg": "res://art/ui/fx_ice_bg.png",
	"fx_ice_fg": "res://art/ui/fx_ice_fg.png",
	"fx_stun_bg": "res://art/ui/fx_stun_bg.png",
	"fx_stun_fg": "res://art/ui/fx_stun_fg.png",
	"el_none": "res://art/ui/el_none.png",
	"el_fire": "res://art/ui/el_fire.png",
	"el_ice": "res://art/ui/el_ice.png",
	"el_elec": "res://art/ui/el_elec.png",
	"el_water": "res://art/ui/el_water.png",
	"el_wood": "res://art/ui/el_wood.png",
	"el_rock": "res://art/ui/el_rock.png",
	"pi_repeater": "res://art/ui/pi_repeater.png",
	"pi_keenedge": "res://art/ui/pi_keenedge.png",
	"pi_heavytip": "res://art/ui/pi_heavytip.png",
	"pi_scope": "res://art/ui/pi_scope.png",
	"pi_midas": "res://art/ui/pi_midas.png",
	"pi_first": "res://art/ui/pi_first.png",
	"pi_deal": "res://art/ui/pi_deal.png",
	"pi_frost": "res://art/ui/pi_frost.png",
	"pi_flame": "res://art/ui/pi_flame.png",
	"pi_pierce": "res://art/ui/pi_pierce.png",
	"pi_split": "res://art/ui/pi_split.png",
	"pi_mortar": "res://art/ui/pi_mortar.png",
	"pi_rage": "res://art/ui/pi_rage.png",
	"pi_headsman": "res://art/ui/pi_headsman.png",
	"pi_overkill": "res://art/ui/pi_overkill.png",
	"pi_giantslay": "res://art/ui/pi_giantslay.png",
	"pi_surge": "res://art/ui/pi_surge.png",
	"pi_bulwark": "res://art/ui/pi_bulwark.png",
	"pi_bolt": "res://art/ui/pi_bolt.png",
	"pi_chainmaster": "res://art/ui/pi_chainmaster.png",
	"pi_wildfire": "res://art/ui/pi_wildfire.png",
	"pi_resonance": "res://art/ui/pi_resonance.png",
	"pi_antibody": "res://art/ui/pi_antibody.png",
	"pi_echo": "res://art/ui/pi_echo.png",
	"pi_eye": "res://art/ui/pi_eye.png",
	"pi_joker": "res://art/ui/pi_joker.png",
}


## 그 등급의 캐릭터 중 하나를 무작위로. **같은 족보라도 매번 다른 얼굴이 나오게** 하는 것이
## 이 게임에서 카드를 뽑는 재미의 절반이다.
static func pick_unit(tier: int, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = []
	for u in UNITS:
		if int(u["tier"]) == tier:
			pool.append(u)
	if pool.is_empty():
		return UNITS[0]
	return pool[rng.randi_range(0, pool.size() - 1)]


static func units_of_tier(tier: int) -> Array:
	var pool: Array = []
	for u in UNITS:
		if int(u["tier"]) == tier:
			pool.append(u)
	return pool


static func unit_by_id(id: String) -> Dictionary:
	for u in UNITS:
		if u["id"] == id:
			return u
	return {}


static func monster_by_id(id: String) -> Dictionary:
	for m in MONSTERS:
		if m["id"] == id:
			return m
	return {}


## 그 몸을 가진 몬스터 전부. 보스는 빼고 준다 — 보스는 boss_of_body() 가 따로 낸다.
static func monsters_of_body(body: String) -> Array:
	var pool: Array = []
	for m in MONSTERS:
		if m["body"] == body and m["kind"] != "boss":
			pool.append(m)
	return pool


## 그 몸의 보스. 테마가 보스를 정한다 — 화산이면 불 보스, 설산이면 얼음 보스다.
static func boss_of_body(body: String) -> Dictionary:
	for m in MONSTERS:
		if m["kind"] == "boss" and m["body"] == body:
			return m
	# 표에 없으면 아무 보스나. 판이 멈추는 것보다 낫다.
	for m2 in MONSTERS:
		if m2["kind"] == "boss":
			return m2
	return {}


static func theme_by_id(id: String) -> Dictionary:
	for t in THEMES:
		if t["id"] == id:
			return t
	return {}


## 몸 분포(weights)에서 몸 하나를 뽑는다.
static func _pick_body(wt: Dictionary, rng: RandomNumberGenerator, skip: Array = []) -> String:
	var total := 0.0
	for b in Balance.MBODY_ORDER:
		if skip.has(b):
			continue
		total += float(wt.get(b, 0.0))
	if total <= 0.0:
		# 분포가 비었거나 전부 걸러졌다. 아무 몸이나 — 판이 멈추는 것보다 낫다.
		for b2 in Balance.MBODY_ORDER:
			if not skip.has(b2):
				return String(b2)
		return String(Balance.MBODY_ORDER[0])
	var r := rng.randf() * total
	for b3 in Balance.MBODY_ORDER:
		if skip.has(b3):
			continue
		r -= float(wt.get(b3, 0.0))
		if r <= 0.0:
			return String(b3)
	return String(Balance.MBODY_ORDER[Balance.MBODY_ORDER.size() - 1])


## 그 테마에서 w 탄에 나올 몬스터 종류(보스 제외). **같은 씨앗이면 언제 물어도 같은 답이다.**
##
## ★ 이것이 상성을 "운"이 아니라 "선택"으로 만드는 열쇠다. 씨앗과 탄 번호만으로 정해지므로
##   **상점이 다음 탄에 나올 몬스터를 정확히 보여 주고**, 플레이어는 그에 맞춰 성역을 짠다.
##   전투가 시작될 때 굴리면 상성은 피할 수 없는 사고가 된다.
##
## 주 속성은 반드시 포함하고 다른 속성도 최소 하나 섞는다.
## 실제 개체 수는 theme_spawns가 주 속성 70~80%로 배분한다.
##
## ★ 1~3탄에는 **느린 놈(육중·주술)을 넣지 않는다.** 육중형은 걷는 속도가 0.8배라 영웅
##   한둘로는 잡을 화력이 안 나오고, 첫 탄부터 크리스탈이 깨진다 — 게임을 켜자마자 벌을
##   받는 셈이다. 앞 세 탄은 무조건 막을 수 있어야 한다.
static func theme_kinds(w: int, theme: Dictionary, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var wt: Dictionary = theme.get("weights", {})
	# 한 탄에 몇 종을 섞을까. ★ 탄 번호를 못 박지 마라 — 40탄에서 100탄이 되면
	#   「후반」의 뜻이 통째로 달라진다. 비율로 적는다.
	var want: int = 2 if w < 6 else (3 if w < Balance.LAST_WAVE * 0.4 else 4)
	var out: Array = []
	var bodies: Array = []
	var main_body := String(theme.get("main_body", ""))
	var main_pool := _kind_pool(main_body, w)
	# 초반 면역 보호로 주 속성을 쓸 수 없는 옛 저장은 허용된 몸으로 진행한다.
	var main_want := mini(main_pool.size(), 1 if want == 2 else 2)
	for i in range(main_want):
		var pick := rng.randi_range(0, main_pool.size() - 1)
		out.append(main_pool.pop_at(pick))
	if not out.is_empty():
		bodies.append(main_body)
	var guard := 0
	while out.size() < want and guard < 400:
		guard += 1
		# 마지막 한 자리인데 아직 몸이 한 가지뿐이면 **다른 몸에서** 뽑는다.
		var skip: Array = []
		if out.size() == want - 1 and bodies.size() == 1:
			skip = bodies
		var body := _pick_body(wt, rng, skip)
		var pool := _kind_pool(body, w)
		if pool.is_empty():
			continue
		var m: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		if out.has(m):
			continue
		out.append(m)
		if not bodies.has(body):
			bodies.append(body)
	if out.is_empty():
		out = wave_kinds_seeded(w, seed_value)
	return out


## 미리보기와 전투가 함께 쓰는 일반 몬스터 목록. 종류 수로 비율이 희석되지 않는다.
static func theme_spawns(w: int, theme: Dictionary, seed_value: int) -> Array:
	var kinds := theme_kinds(w, theme, seed_value)
	var main_body := String(theme.get("main_body", ""))
	var wt: Dictionary = theme.get("weights", {})
	var by_body: Dictionary = {}
	for monster in kinds:
		var body := String(monster["body"])
		if not by_body.has(body):
			by_body[body] = []
		by_body[body].append(monster)
	var count := Balance.wave_count(w)
	var main_count := 0
	if by_body.has(main_body):
		main_count = roundi(count * float(wt.get(main_body, 0.75)))
		if by_body.size() == 1:
			main_count = count
	var out: Array = []
	for i in range(main_count):
		out.append(by_body[main_body][i % by_body[main_body].size()])
	var side_bodies: Array = []
	var side_total := 0.0
	for body in by_body:
		if body != main_body:
			side_bodies.append(body)
			side_total += float(wt.get(body, 0.0))
	var remaining := count - main_count
	var amounts: Array[int] = []
	var fractions: Array[float] = []
	var assigned := 0
	for body in side_bodies:
		var share := float(wt.get(body, 0.0)) / side_total if side_total > 0.0 else 1.0 / side_bodies.size()
		var exact := remaining * share
		amounts.append(floori(exact))
		fractions.append(exact - floor(exact))
		assigned += floori(exact)
	for i in range(remaining - assigned):
		var best := 0
		for j in range(1, fractions.size()):
			if fractions[j] > fractions[best]:
				best = j
		amounts[best] += 1
		fractions[best] = -1.0
	for i in range(side_bodies.size()):
		var pool: Array = by_body[side_bodies[i]]
		for j in range(amounts[i]):
			out.append(pool[j % pool.size()])
	return out


## 그 몸에서 w 탄에 쓸 수 있는 몬스터.
##
## ★ 앞 **다섯** 탄에는 **면역을 가진 몸을 안 넣는다**(바위). 1탄에는 영웅이 **하나뿐**이라
##   그 하나가 전기면 바위에게 한 톨도 못 넣는다 — 피할 길이 없다. 편성을 미리 보여
##   줘도 소용없다. 바꿀 영웅이 없기 때문이다. 자동 플레이에서 실제로 1탄 평균
##   크리스탈 -0.58 로 나왔다(원래 1~6탄은 하나도 안 잃어야 한다).
## ★★ **셋에서 다섯으로 늘린 것은 캐릭터가 늘면서다.** 등급에 셋뿐이던 시절에는 앞
##   탄에 **같은 캐릭터를 두 번 뽑는 일이 흔했고**(1/3) 겹치면 화력이 곧 두 배였다.
##   여든이던 시절에는 그 확률이 1/8 까지 떨어져 **앞 탄의 겹침이 사실상 사라졌고**,
##   4탄에서 크리스탈이 깨지는 판이 열둘 중 하나씩 나왔다(`verify.sh` 7단계가 잡았다).
##   ☆ 지금은 등급마다 **다섯**이라 겹칠 확률이 1/5 로 되돌아왔다 — 그만큼 앞 탄이
##     다시 두꺼워졌으므로, 이 다섯 탄을 줄일 여지가 생기면 여기부터 재 봐라.
##   ☆ 몬스터를 더 얇게 하는 것으로는 안 풀린다. 전기 영웅에게 바위는 **0배**라,
##     얼마나 얇든 곱하면 0 이기 때문이다. 막을 수 있는 것은 「안 나오게」뿐이다.
## ★ 앞 세 탄에는 **느린 놈(육중·주술)도 안 넣는다.** 육중형은 걷는 속도가 0.8배라
##   영웅 한둘로는 잡을 화력이 안 나오고, 첫 탄부터 크리스탈이 깨진다 — 게임을
##   켜자마자 벌을 받는 셈이다. 앞 세 탄은 무조건 막을 수 있어야 한다.
static func _kind_pool(body: String, w: int) -> Array:
	if w <= 5 and not Balance.body_immune(body).is_empty():
		return []
	var pool: Array = []
	for m in monsters_of_body(body):
		if w <= 3 and (m["kind"] == "tank" or m["kind"] == "caster"):
			continue
		# ★ 첫 두 탄은 **떼거리만** 나온다. 쾌속형은 걷는 속도가 1.7배라 열일곱 초면
		#   크리스탈에 닿는데, 그때 플레이어는 영웅이 **하나**다. 그 하나가 하필
		#   저항에 걸리는 속성이면(불 영웅 x 물·얼음 몸이면 둘 다 반) 화력이 절반이 되어
		#   막을 수가 없다 — 자동 플레이 24판에서 1탄 평균 크리스탈 -0.12 로 나왔다.
		#   첫 두 탄은 게임을 켠 사람이 처음 보는 장면이다. 거기서 벌을 주면 안 된다.
		if w <= 2 and m["kind"] != "swarm":
			continue
		pool.append(m)
	return pool


## 테마를 모르는 자리(가짜 Run 을 쓰는 검사기)가 쓰는 되돌림 길. 몸을 안 가리고 뽑는다.
static func wave_kinds_seeded(w: int, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return wave_kinds(w, rng)


static func wave_kinds(w: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = []
	for m in MONSTERS:
		if m["kind"] == "boss":
			continue
		if w <= 3 and (m["kind"] == "tank" or m["kind"] == "caster"):
			continue
		# 앞 세 탄에는 면역을 가진 몸을 안 넣는다 (_kind_pool 주석 참고).
		if w <= 3 and not Balance.body_immune(String(m["body"])).is_empty():
			continue
		pool.append(m)
	if pool.is_empty():
		pool = MONSTERS.duplicate()
	var out: Array = []
	var want: int = 2 if w < 6 else 3
	var guard := 0
	while out.size() < want and guard < 200:
		guard += 1
		var m2: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		if not out.has(m2):
			out.append(m2)
	return out


## 그 테마에 **나올 수 있는** 몬스터 전부(보스 제외). 난수를 안 쓴다.
## 씨앗을 모르는 자리(검사기·미리보기)에서 "이 테마에는 이런 놈들이 있다"를 보일 때 쓴다.
static func theme_pool(theme: Dictionary, w: int = 99) -> Array:
	var wt: Dictionary = theme.get("weights", {})
	var out: Array = []
	for b in Balance.MBODY_ORDER:
		if float(wt.get(b, 0.0)) <= 0.0:
			continue
		for m in _kind_pool(String(b), w):
			if not out.has(m):
				out.append(m)
	return out
