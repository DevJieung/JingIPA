import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/app_repository.dart';
import '../data/demo_repository.dart';
import '../data/invite_links.dart';
import '../data/location_access.dart';
import 'guest_join_dialog.dart';
import '../domain/models.dart';
import 'theme.dart';
import 'app_banner_strip.dart';
import 'feature_screens.dart';
import 'profile_permissions.dart';
import 'pod_lobby.dart';
import 'name_guide.dart';
import 'profile_editor.dart';
import 'load_notice.dart';

class MeokkiriApp extends StatelessWidget {
  const MeokkiriApp({
    required this.repository,
    this.locationAccess = const LocationAccess(),
    super.key,
  });
  final AppRepository repository;
  final LocationAccess locationAccess;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '먹끼리 · 오늘 밥, 우리끼리',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    builder: (context, child) =>
        RepaintBoundary(key: const Key('app-preview'), child: child!),
    home: AppShell(repository: repository, locationAccess: locationAccess),
  );
}

String clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
String remaining(DateTime target, DateTime now) {
  final seconds = target.difference(now).inSeconds.clamp(0, 999999);
  return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class AppShell extends StatefulWidget {
  const AppShell({
    required this.repository,
    this.locationAccess = const LocationAccess(),
    super.key,
  });
  final AppRepository repository;
  final LocationAccess locationAccess;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppRepository get repo => widget.repository;
  int _tab = 1;
  String? _channelId;
  bool _busy = false;
  bool _joiningLink = false;
  String? _selectionOwner;
  final _invites = InviteLinks();
  @override
  void initState() {
    super.initState();
    unawaited(_invites.initialize());
  }

  final _name = TextEditingController();
  @override
  void dispose() {
    _invites.dispose();
    _name.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          margin: EdgeInsets.fromLTRB(16, 0, 16, repo.user == null ? 16 : 88),
          content: Text(text),
        ),
      );
    }
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (success != null) _message(success);
    } catch (error) {
      _message(
        error is LunchException ? error.message : '연결을 확인하고 다시 시도해 주세요.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinAsGuest() async {
    _joiningLink = true;
    try {
      final joined = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => GuestJoinDialog(
          initialCode: _invites.pending ?? '',
          join: (name, code) async {
            // The dialog owns joining; do not also auto-join the pending link.
            _invites.take();
            await repo.signInGuest(name, code);
          },
        ),
      );
      if (joined == true && mounted) {
        setState(() => _tab = 1);
        _message(repo.channelJoinMessage);
      }
    } finally {
      _joiningLink = false;
    }
  }

  Future<void> _signOut() async {
    if (repo.isGuest &&
        !await _confirm(
          '비회원 참여를 종료할까요?',
          '계정을 연결하지 않고 로그아웃하면 이 모임과 참여 기록을 다시 찾지 못할 수 있어요. 내 프로필에서 먼저 계정을 연결할 수 있어요.',
          action: '로그아웃',
        )) {
      return;
    }
    await _run(repo.signOut);
  }

  Future<bool> _confirm(
    String title,
    String description, {
    String action = '참여 취소',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          scrollable: true,
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('돌아가기'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                minimumSize: const Size(90, actionHeight),
              ),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([repo, _invites]),
    builder: (context, _) {
      if (_selectionOwner != repo.user?.id) {
        _selectionOwner = repo.user?.id;
        _channelId = null;
      }
      final session = repo.sessionStatus;
      if ([
        SessionStatus.restoring,
        SessionStatus.loadingProfile,
        SessionStatus.failed,
      ].contains(session)) {
        return Scaffold(
          backgroundColor: paper,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: LoadNotice(
                    key: const Key('session-loading'),
                    message: session == SessionStatus.failed
                        ? repo.connectionError ?? '시작 정보를 확인하지 못했어요.'
                        : '먹끼리를 준비하고 있어요.',
                    failed: session == SessionStatus.failed,
                    onRetry: () => _run(repo.retrySession),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      final signedIn = repo.user != null;
      final channels = repo.channels;
      final channel =
          channels
              .where((c) => c.id == (repo.selectedChannelId ?? _channelId))
              .firstOrNull ??
          channels.firstOrNull;
      if (signedIn &&
          repo.user!.name.isNotEmpty &&
          _invites.pending != null &&
          !_joiningLink) {
        _joiningLink = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final code = _invites.take()!;
          _joiningLink = false;
          _run(() async {
            await repo.joinChannel(code);
            _message(repo.channelJoinMessage);
          });
        });
      }
      final ready = signedIn && repo.user!.name.isNotEmpty;
      return Scaffold(
        backgroundColor: paper,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = ready && constraints.maxWidth >= 1000;
            if (!ready) {
              return Row(
                children: [
                  if (constraints.maxWidth >= 1000)
                    Expanded(child: _desktopBrand()),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: SafeArea(
                          child: signedIn ? _setName() : _welcome(),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
            return SafeArea(
              child: Row(
                children: [
                  if (desktop) _desktopNavigation(),
                  Expanded(
                    child: Column(
                      children: [
                        _header(),
                        if (repo.connectionError != null)
                          MaterialBanner(
                            content: Text(repo.connectionError!),
                            actions: [
                              TextButton(
                                onPressed: () => _run(repo.refresh),
                                child: const Text('다시 연결'),
                              ),
                            ],
                          ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: _tab == 1 || _tab == 0 ? 1280 : 760,
                              ),
                              child: RefreshIndicator(
                                onRefresh: repo.refresh,
                                child: _mainContent(channel, channels),
                              ),
                            ),
                          ),
                        ),
                        if (!desktop && appBannerStripEnabled)
                          const AppBannerStrip(),
                        if (!desktop) _navigation(),
                        if (_busy)
                          Semantics(
                            liveRegion: true,
                            label: '처리 중',
                            child: const LinearProgressIndicator(minHeight: 2),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );

  Widget _mainContent(LunchChannel? channel, List<LunchChannel> channels) {
    if ((_tab == 0 || _tab == 1) &&
        channels.isEmpty &&
        repo.channelsStatus != LoadStatus.ready) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _pageActions(_tab == 1 ? '식당 정하기' : '내 모임 관리'),
          const SizedBox(height: 16),
          LoadNotice(
            key: const Key('channels-loading'),
            message: repo.channelsStatus == LoadStatus.failed
                ? '모임을 불러오지 못했어요.'
                : '내 모임을 불러오고 있어요.',
            failed: repo.channelsStatus == LoadStatus.failed,
            onRetry: () => _run(repo.retrySession),
          ),
        ],
      );
    }
    if (_tab == 1) return _today(channel);
    if (_tab == 0) return _channelList(channels);
    if (_tab == 3) return _profile();
    return FavoritesPanel(
      channelName: channel?.name,
      repository: repo,
      onChoose: (r) async {
        if (channel == null) {
          _message('먼저 채널을 선택해 주세요.');
          return;
        }
        final round = repo.roundFor(channel.id);
        if (round == null ||
            ![
              RoundPhase.submission,
              RoundPhase.adjusting,
            ].contains(round.phase)) {
          _message('식당선택에서 라운드를 먼저 열어 주세요.');
          return;
        }
        await featureSheet<void>(
          context,
          PodCreateForm(
            repository: repo,
            channel: channel,
            initialRestaurant: r,
            locationAccess: widget.locationAccess,
          ),
        );
        if (mounted) setState(() => _tab = 1);
      },
    );
  }

  void _selectTab(int index) {
    setState(() => _tab = index);
    if (index == 0) unawaited(repo.loadChannelSummaries());
    if (index == 2) unawaited(repo.loadFavorites());
  }

  Widget _desktopNavigation() => Container(
    key: const Key('desktop-navigation'),
    width: 208,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(padding: EdgeInsets.all(28), child: BrandMark()),
        const SizedBox(height: 20),
        for (final (index, icon, label) in [
          (0, Icons.people_outline_rounded, '내 모임'),
          (1, Icons.rice_bowl_outlined, '식당선택'),
          (2, Icons.favorite_border_rounded, '내식당 관리'),
          (3, Icons.person_outline_rounded, '내 정보'),
        ])
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Material(
              color: _tab == index ? sageSurface : Colors.white,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                selected: _tab == index,
                selectedTileColor: sageSurface,
                selectedColor: forest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Icon(icon, size: 22),
                title: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () => _selectTab(index),
              ),
            ),
          ),
        const Spacer(),
        const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ElephantArt(size: 68, scene: ElephantScene.together),
              SizedBox(height: 12),
              Text(
                '오늘 밥도, 우리끼리.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _desktopBrand() => Container(
    color: sageSurface,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandMark(),
              const SizedBox(height: 44),
              const Tag('#내가가고싶은식당', color: forest, foreground: Colors.white),
              const SizedBox(height: 20),
              const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '눈치 보지 말고,\n취향대로 고르고.\n'),
                    TextSpan(
                      text: '같이 먹으러 가요!',
                      style: TextStyle(color: orange),
                    ),
                  ],
                ),
                style: TextStyle(
                  fontSize: 42,
                  height: 1.4,
                  letterSpacing: -2,
                  fontWeight: FontWeight.w900,
                  color: forest,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '밥팟에서, 마음 맞는 동료와 함께.\n먹고 싶은 마음만큼은 편하게 나눠요.',
                style: TextStyle(fontSize: 15, height: 1.9, color: muted),
              ),
              const SizedBox(height: 28),
              const Center(
                child: ElephantArt(size: 230, scene: ElephantScene.together),
              ),
              const SizedBox(height: 20),
              const Text(
                '먹고 싶은 마음만큼은, 편하게.',
                style: TextStyle(color: forest, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _welcome() => ListView(
    key: const Key('welcome-scroll'),
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
    children: [
      const BrandMark(),
      const SizedBox(height: 32),
      Text(
        '오늘 밥,\n먹고 싶은 곳으로.',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 12),
      const Text(
        '팟을 만들고 참여하며,\n마음 맞는 동료와 함께 먹어요.',
        style: TextStyle(color: muted, fontSize: 15, height: 1.7),
      ),
      const Center(
        child: ElephantArt(size: 136, scene: ElephantScene.together),
      ),
      const Surface(
        color: sageSurface,
        child: Column(
          children: [
            _WelcomeStep(
              number: '1',
              title: '밥팟을 만들어요',
              detail: '팟 이름과 최소 인원을 정해요. 식당은 직접 입력에서 비워둘 수 있어요.',
            ),
            Divider(height: 24),
            _WelcomeStep(
              number: '2',
              title: '마음 맞는 동료와 모여요',
              detail: '한 번의 마감으로 팟이 확정돼요.',
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      if (repo.isLocal) ...[
        const Tag('로컬 Firebase 테스트'),
        const SizedBox(height: 12),
        const Text(
          '테스트 계정을 골라주세요. 다른 창에서 다른 계정으로 접속하면 실시간으로 함께 테스트할 수 있어요.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        for (final actor in ['a', 'b', 'c', 'd', 'e', 'f'])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              key: Key('local-login-$actor'),
              onPressed: _busy
                  ? null
                  : () => _run(() => repo.signInLocal(actor)),
              child: Text(
                '테스트 ${actor.toUpperCase()}로 로그인${actor == 'e'
                    ? ' · 프리미엄'
                    : actor == 'f'
                    ? ' · 초대 테스트'
                    : ''}',
              ),
            ),
          ),
        const Text(
          'Auth·Firestore·Functions 에뮬레이터를 사용해요.\n계정과 식당은 테스트 데이터이며 실제 SSO·결제는 연결하지 않아요.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('guest-join'),
          onPressed: _busy ? null : _joinAsGuest,
          child: const Text('비회원으로 참여하기'),
        ),
      ] else if (!repo.isDemo) ...[
        if (_invites.pending != null) ...[
          const Text(
            '초대받은 모임이 있어요. 로그인하거나 비회원으로 참여해 주세요.',
            style: TextStyle(fontSize: 13, color: forest),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: _busy ? null : () => _run(repo.signInGoogle),
          icon: const GoogleMark(),
          label: const Text('Google로 계속하기'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _run(repo.signInApple),
          icon: const Icon(Icons.apple, size: 23),
          label: const Text('Apple로 계속하기'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('guest-join'),
          onPressed: _busy ? null : _joinAsGuest,
          icon: const Icon(Icons.person_outline_rounded),
          label: const Text('비회원으로 참여하기'),
        ),
      ] else ...[
        FilledButton.icon(
          key: const Key('enter-demo'),
          onPressed: _busy ? null : () => _run(repo.enterDemo),
          icon: const Icon(Icons.arrow_forward_rounded, size: 19),
          label: const Text('먹끼리 체험하기'),
        ),
        const SizedBox(height: 12),
        const Text(
          '체험용 동료와 식당으로 모든 단계를 둘러볼 수 있어요.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
      const SizedBox(height: 24),
      const Text(
        '먹고 싶은 마음만큼은, 편하게.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: muted),
      ),
    ],
  );
  Widget _setName() => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      const SizedBox(height: 24),
      const LunchArt(size: 80),
      const SizedBox(height: 20),
      const NameSetupIntro(),
      const SizedBox(height: 24),
      TextField(
        controller: _name,
        maxLength: 20,
        decoration: const InputDecoration(labelText: '이름', hintText: '예: 윤수빈'),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _busy ? null : () => _run(() => repo.updateName(_name.text)),
        child: const Text('먹끼리 시작하기'),
      ),
      TextButton(
        onPressed: () => _run(repo.signOut),
        child: const Text('다른 계정으로 로그인'),
      ),
    ],
  );
  Widget _header() => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: line)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    child: Row(
      children: [
        if (MediaQuery.sizeOf(context).width < 1000)
          const BrandMark()
        else
          Text('오늘 밥, 우리끼리', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              if (repo.isDemo)
                TextButton(onPressed: _demoTools, child: const Text('체험 모드')),
              if (repo.isLocal)
                TextButton(
                  key: const Key('local-tools'),
                  onPressed: _localTools,
                  child: const Text('로컬 Firebase'),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _pageActions(String title) => PageHeading(
    title: title,
    onHelp: () => featureSheet<void>(context, TabHelpSheet(tab: _tab)),
  );

  Widget _navigation() => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: line)),
    ),
    child: NavigationBar(
      backgroundColor: Colors.white,
      elevation: 0,
      height: 72,
      indicatorColor: sageSurface,
      selectedIndex: _tab,
      onDestinationSelected: _selectTab,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.people_outline_rounded),
          selectedIcon: Icon(Icons.people_rounded),
          label: '내 모임',
        ),
        NavigationDestination(
          icon: Icon(Icons.rice_bowl_outlined),
          selectedIcon: Icon(Icons.rice_bowl),
          label: '식당선택',
        ),
        NavigationDestination(
          icon: Icon(Icons.favorite_border_rounded),
          selectedIcon: Icon(Icons.favorite_rounded),
          label: '내식당 관리',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: '내 정보',
        ),
      ],
    ),
  );

  Widget _today(LunchChannel? channel) => PodLobby(
    key: ValueKey(channel?.id),
    repository: repo,
    channel: channel,
    locationAccess: widget.locationAccess,
    onChangeChannel: () => _chooseChannel(channel),
    onHelp: () => featureSheet<void>(context, const TabHelpSheet(tab: 1)),
  );

  Future<void> _chooseChannel(LunchChannel? selected) async {
    final id = await featureSheet<String>(
      context,
      AnimatedBuilder(
        animation: repo,
        builder: (sheetContext, _) => SizedBox(
          key: const Key('channel-picker'),
          height: MediaQuery.sizeOf(sheetContext).height * .65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '모임 선택',
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (repo.channels.isEmpty)
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '참여한 모임이 없어요.\n내 모임에서 만들거나 초대 코드로 참여해 주세요.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: repo.channels.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final channel = repo.channels[index];
                      final active = channel.id == selected?.id;
                      return ListTile(
                        key: Key('choose-channel-${channel.id}'),
                        selected: active,
                        selectedTileColor: sageSurface,
                        leading: const Icon(Icons.people_outline_rounded),
                        title: Text(channel.name),
                        subtitle: Text('${channel.members.length}명'),
                        trailing: active
                            ? const Icon(Icons.check_rounded, color: forest)
                            : null,
                        onTap: () => Navigator.pop(sheetContext, channel.id),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted && id != null && repo.channels.any((c) => c.id == id)) {
      setState(() => _channelId = id);
      unawaited(repo.selectChannel(id));
    }
  }

  Widget _channelList(List<LunchChannel> channels) => ListView(
    key: const PageStorageKey('channels'),
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
    children: [
      _pageActions('내 모임 관리'),
      const SizedBox(height: 18),
      ResponsiveCards(
        children: channels
            .map(
              (c) => Surface(
                key: Key('channel-card-${c.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.people_alt_outlined, color: forest),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Tooltip(
                            message: c.name,
                            child: Text(
                              c.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                        Tag('${c.members.length}명'),
                        IconButton(
                          key: Key('channel-members-${c.id}'),
                          tooltip: '초대 및 구성원 관리',
                          onPressed: () => _channelMembers(c),
                          icon: const Icon(Icons.more_horiz_rounded, size: 22),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: _channelStatus(c)),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: Key('open-channel-${c.id}'),
                      onPressed: () => setState(() {
                        _channelId = c.id;
                        unawaited(repo.selectChannel(c.id));
                        _tab = 1;
                      }),
                      child: const Text('식당선택하러가기'),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 10),
      if (!repo.isGuest)
        OutlinedButton.icon(
          onPressed: () => _channelForm(join: false),
          icon: const Icon(Icons.add_rounded),
          label: const Text('새 채널 만들기'),
        ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: () => _channelForm(join: true),
        child: const Text('초대 코드로 참여하기'),
      ),
      const SizedBox(height: 16),
      const Text(
        '함께 밥을 먹을 모임을 고른 뒤 식당을 정해요.',
        textAlign: TextAlign.center,
        style: TextStyle(color: muted, fontSize: 12),
      ),
    ],
  );

  Future<void> _channelMembers(LunchChannel initial) => _sheet(
    AnimatedBuilder(
      animation: repo,
      builder: (ctx, _) {
        final channel = repo.channels
            .where((c) => c.id == initial.id)
            .firstOrNull;
        if (channel == null) return const SizedBox.shrink();
        final owner = channel.ownerId == repo.user?.id;
        final round = repo.roundFor(channel.id);
        final locked = [
          RoundPhase.submission,
          RoundPhase.adjusting,
        ].contains(round?.phase);
        final leaveLocked =
            locked ||
            round?.phase == RoundPhase.submission ||
            (channel.roundId != null && round?.id != channel.roundId);
        return SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .72,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('채널 구성원', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(channel.name, style: const TextStyle(color: forest)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('invite-channel'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _inviteSheet(channel);
                  },
                  icon: const Icon(Icons.link_rounded, size: 20),
                  label: const Text('동료 초대'),
                ),
                const SizedBox(height: 8),
                Text(
                  leaveLocked
                      ? '라운드 진행 중에는 채널에서 나갈 수 없어요. 종료 후 이용해 주세요.${locked ? ' 모집 중에는 내보내기도 할 수 없어요.' : ''}'
                      : owner
                      ? '채널장만 동료를 내보낼 수 있어요. 라운드장 권한과는 별개예요.'
                      : '내가 참여한 채널에서 나갈 수 있어요.',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final person in channel.members.entries)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.person_outline_rounded,
                            color: forest,
                          ),
                          title: Text(
                            '${person.value}${person.key == repo.user?.id ? ' (나)' : ''}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: person.key == channel.ownerId
                              ? const Text('채널장')
                              : null,
                          trailing: owner && person.key != repo.user?.id
                              ? TextButton(
                                  key: Key('remove-member-${person.key}'),
                                  onPressed: locked
                                      ? null
                                      : () async {
                                          if (await _confirm(
                                            '${person.value} 님을 내보낼까요?',
                                            '이 채널의 구성원에서 제외돼요. 팟 참여가 해제돼요.',
                                            action: '내보내기',
                                          )) {
                                            await _run(
                                              () => repo.removeChannelMember(
                                                channel.id,
                                                person.key,
                                              ),
                                              success: '채널에서 내보냈어요.',
                                            );
                                          }
                                        },
                                  child: const Text('내보내기'),
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('leave-channel'),
                  onPressed: leaveLocked
                      ? null
                      : () async {
                          final next = channel.members.entries
                              .where((p) => p.key != repo.user?.id)
                              .firstOrNull;
                          final handoff = owner
                              ? next == null
                                    ? '\n마지막 구성원이 나가면 채널이 닫혀요.'
                                    : '\n${next.value} 님에게 채널장 권한을 넘겨요.'
                              : '';
                          if (await _confirm(
                            '채널에서 나갈까요?',
                            '채널 구성원에서 제외되며 채널의 라운드에 참여할 수 없어요.$handoff',
                            action: '나가기',
                          )) {
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _run(
                              () => repo.leaveChannel(channel.id),
                              success: '채널에서 나왔어요.',
                            );
                          }
                        },
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('채널 나가기'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _channelStatus(LunchChannel channel) {
    final cached = repo.roundFor(channel.id);
    final round = cached?.id == channel.roundId ? cached : null;
    final loading = round == null && channel.roundId != null;
    final phase = round?.phase;
    final background = loading
        ? sageSurface
        : switch (phase) {
            RoundPhase.submission || RoundPhase.adjusting => recruitingSurface,
            RoundPhase.finalized => sageSurface,
            RoundPhase.cancelled || null => channelOpenSurface,
          };
    const foreground = forest;
    final detailColor =
        phase == RoundPhase.submission || phase == RoundPhase.adjusting
        ? forest
        : muted;
    final status = loading
        ? '상태 확인 중'
        : switch (phase) {
            RoundPhase.submission => '팟 모집 중',
            RoundPhase.adjusting => '팟 모집 중',
            RoundPhase.finalized => '최종 결정',
            RoundPhase.cancelled || null => 'Open',
          };
    final detail = loading
        ? (repo.connectionError ?? '라운드 상태를 불러오고 있어요.')
        : switch (phase) {
            RoundPhase.submission => '팟을 만들고 함께 먹을 동료를 모으고 있어요.',
            RoundPhase.adjusting => '마감 전까지 팟에 참여하거나 옮길 수 있어요.',
            RoundPhase.finalized =>
              round!.myPodId == null
                  ? '이번 라운드에는 팟에 참여하지 않았어요.'
                  : '내 팟 · ${round.pods.where((p) => p.id == round.myPodId).firstOrNull?.name ?? '마감'}',
            RoundPhase.cancelled => '이전 라운드가 종료됐어요. 새 라운드를 열 수 있어요.',
            null => '새 라운드를 열 수 있어요.',
          };
    return Container(
      key: Key('channel-status-${channel.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(detail, style: TextStyle(fontSize: 12, color: detailColor)),
          if (phase == RoundPhase.finalized && round!.myRestaurant != null) ...[
            const SizedBox(height: 6),
            Text(
              round.companions.isEmpty
                  ? '함께할 동료 · 같은 식당을 고른 동료가 없어요.'
                  : '함께할 동료 · ${round.companions.map((p) => p.name).join(' · ')}',
              style: TextStyle(fontSize: 12, color: foreground),
            ),
          ],
        ],
      ),
    );
  }

  Widget _profile() => ListView(
    key: const PageStorageKey('profile'),
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
    children: [
      _pageActions('내 프로필'),
      const SizedBox(height: 16),
      Surface(
        child: Row(
          children: [
            Semantics(
              label: '이름과 이모지 편집',
              button: true,
              child: InkWell(
                key: const Key('profile-emoji'),
                onTap: _editProfile,
                child: EmojiAvatar(repo.user!.emoji, size: 58),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                repo.user!.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: '프로필 편집',
              onPressed: _editProfile,
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (repo.isGuest) ...[
        Surface(
          key: const Key('guest-account-card'),
          color: sageSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '비회원으로 참여 중',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                '로그아웃·앱 삭제·브라우저 데이터 삭제 시 기록을 다시 찾지 못할 수 있어요. '
                '계정을 연결하면 모임과 참여 기록을 그대로 이어갈 수 있어요.',
                style: TextStyle(fontSize: 12, color: muted, height: 1.6),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('guest-link-google'),
                onPressed: _busy
                    ? null
                    : () => _run(
                        repo.signInGoogle,
                        success: '계정을 연결했어요. 참여 기록은 그대로예요.',
                      ),
                child: const Text('Google 계정 연결'),
              ),
              OutlinedButton(
                key: const Key('guest-link-apple'),
                onPressed: _busy
                    ? null
                    : () => _run(
                        repo.signInApple,
                        success: '계정을 연결했어요. 참여 기록은 그대로예요.',
                      ),
                child: const Text('Apple 계정 연결'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
      AttendanceCard(attendance: repo.attendance, repository: repo),
      const SizedBox(height: 16),
      _settingsLabel('개인 설정'),
      Surface(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            ProfilePermissions(
              repository: repo,
              locationAccess: widget.locationAccess,
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _settingsLabel('도움과 문의'),
      Surface(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            SettingsRow(
              key: const Key('customer-voice'),
              icon: Icons.chat_bubble_outline_rounded,
              title: '운영자에게 메시지 보내기',
              subtitle: '고객의 소리 · 나와 운영자만 확인해요',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CustomerMessagesScreen(repository: repo),
                ),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            SettingsRow(
              icon: Icons.fact_check_outlined,
              title: '내 식당 등록 제보',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ReportsScreen(repository: repo),
                ),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            if (repo.isAdmin) ...[
              SettingsRow(
                key: const Key('admin-customer-voice'),
                icon: Icons.admin_panel_settings_outlined,
                title: '운영자 · 고객의 소리 확인',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        CustomerMessagesScreen(repository: repo, admin: true),
                  ),
                ),
              ),
              SettingsRow(
                key: const Key('admin-reports'),
                icon: Icons.fact_check_outlined,
                title: '운영자 · 식당 제보 관리',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ReportsScreen(repository: repo, admin: true),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
      Surface(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          key: const PageStorageKey('account-settings'),
          title: const Text(
            '계정 관리',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          children: [
            SettingsRow(
              icon: Icons.logout_rounded,
              title: '로그아웃',
              onTap: _signOut,
            ),
            SettingsRow(
              icon: Icons.person_remove_outlined,
              title: '계정 및 내 데이터 삭제',
              onTap: () async {
                if (repo.channels.any(
                  (c) => [
                    RoundPhase.submission,
                    RoundPhase.adjusting,
                  ].contains(repo.roundFor(c.id)?.phase),
                )) {
                  _message('라운드 진행 중에는 계정을 삭제할 수 없어요. 라운드 종료 후 이용해 주세요.');
                  return;
                }
                if (await _confirm(
                  '먹끼리에서 탈퇴할까요?',
                  '채널 소속과 식당 선택, 프로필을 삭제해요. 이 작업은 되돌릴 수 없어요.',
                  action: '탈퇴하기',
                )) {
                  await _run(repo.deleteAccount);
                }
              },
            ),
          ],
        ),
      ),
      if (repo.isDemo)
        TextButton.icon(
          onPressed: _demoTools,
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('체험 도구 열기'),
        ),
      if (repo.isLocal)
        TextButton.icon(
          onPressed: _localTools,
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('로컬 Firebase 테스트 도구'),
        ),
    ],
  );

  Widget _settingsLabel(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        color: muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Future<void> _sheet(Widget child) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SafeArea(top: false, child: SingleChildScrollView(child: child)),
    ),
  );
  Future<void> _channelForm({required bool join}) async {
    if (!join && repo.isGuest) {
      _message('모임을 만들려면 내 프로필에서 계정을 연결해 주세요.');
      setState(() => _tab = 3);
      return;
    }
    final controller = TextEditingController();
    await _sheet(
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              join ? '초대받은 채널에 들어가기' : '우리끼리 채널 만들기',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              join
                  ? '동료에게 받은 코드를 입력하면 바로 입장해요. 모집 중에도 함께 참여할 수 있어요.'
                  : '평소 함께 밥을 먹는 동료들을 모아보세요.',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: join ? 32 : 30,
              textCapitalization: join
                  ? TextCapitalization.characters
                  : TextCapitalization.none,
              decoration: InputDecoration(
                labelText: join ? '초대 코드' : '채널 이름',
                hintText: join ? 'MEOK26' : '예: 디자인팀 밥 메이트',
              ),
            ),
            const SizedBox(height: 17),
            FilledButton(
              onPressed: () async {
                final value = controller.text;
                Navigator.pop(context);
                await _run(() async {
                  if (join) {
                    await repo.joinChannel(value);
                    _message(repo.channelJoinMessage);
                  } else {
                    await repo.createChannel(value);
                    _message('새 채널을 만들었어요.');
                  }
                });
                if (mounted) setState(() => _tab = 0);
              },
              child: Text(join ? '모임에 참여하기' : '채널 만들기'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _inviteSheet(LunchChannel channel) async {
    final origin = Uri.base;
    final link = origin.hasScheme && origin.scheme.startsWith('http')
        ? origin
              .replace(
                queryParameters: {'invite': channel.inviteCode},
                fragment: '',
              )
              .toString()
        : 'meokkiri://join?invite=${channel.inviteCode}';
    await _sheet(
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '같이 먹는 동료를 초대해요',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            SelectableText(
              channel.inviteCode,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                color: forest,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '코드를 가진 동료는 승인 없이 가입할 수 있어요.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: channel.inviteCode),
                );
                _message('초대 코드를 복사했어요.');
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('초대 코드 복사'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                _message('초대 링크를 복사했어요.');
              },
              child: const Text('초대 링크 복사'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editProfile() => editProfile(context, repo);

  Future<void> _localTools() async {
    final channel =
        repo.channels.where((c) => c.id == _channelId).firstOrNull ??
        repo.channels.firstOrNull;
    await _sheet(
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '로컬 Firebase 테스트 도구',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              '시간 이동과 샘플 데이터 초기화는 로컬에서만 작동해요.\nE는 A/B를 Red로 지정한 프리미엄 계정이에요.\n초대 코드: LOCAL123 · F로 가입을 테스트하세요.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (channel != null) ...[
              for (final action in const [
                ('reveal', '식당 지금 공개하기', Icons.lock_open_rounded),
                ('move', '동료 A의 식당 이동', Icons.swap_horiz_rounded),
                ('finalize', '추가 시간 마감하기', Icons.done_all_rounded),
              ])
                ListTile(
                  leading: Icon(action.$3),
                  title: Text(action.$2),
                  onTap: () {
                    Navigator.pop(context);
                    _run(
                      () => repo.localAction(action.$1, channelId: channel.id),
                    );
                  },
                ),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('로그아웃하고 테스트 계정 바꾸기'),
              onTap: () {
                Navigator.pop(context);
                _run(repo.signOut);
              },
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded),
              title: const Text('로컬 데이터 초기화'),
              subtitle: const Text('모든 테스트 창의 데이터가 함께 초기화돼요.'),
              onTap: () async {
                Navigator.pop(context);
                if (await _confirm(
                  '로컬 데이터를 초기화할까요?',
                  '로컬 채널·선택·테스트 계정을 지우고 A~F 샘플을 다시 만들어요. 다른 테스트 창도 다시 로그인해 주세요.',
                  action: '초기화',
                )) {
                  await _run(() => repo.localAction('reset'));
                  if (mounted) {
                    setState(() {
                      _tab = 1;
                      _channelId = null;
                    });
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _demoTools() async {
    final demo = repo;
    if (demo is! DemoRepository) return;
    final channel =
        repo.channels.where((c) => c.id == _channelId).firstOrNull ??
        repo.channels.firstOrNull;
    await _sheet(
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '시간을 건너뛰며 체험해요',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              '실제 동료나 식당 데이터가 아닌 체험용 환경이에요.\n시간 이동과 동료의 선택을 직접 시뮬레이션할 수 있어요.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 18),
            if (channel != null && repo.roundFor(channel.id) != null) ...[
              ListTile(
                leading: const Icon(Icons.done_all_rounded),
                title: const Text('모집 마감 시각으로 이동'),
                onTap: () {
                  Navigator.pop(context);
                  _run(() => demo.finishPodDemo(channel.id));
                },
              ),
              const Divider(),
              const Text(
                '다른 동료의 화면으로 보기',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                children: channel.members.entries
                    .map(
                      (e) => ActionChip(
                        label: Text(
                          e.value,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _run(() => demo.switchPerson(e.key));
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _run(demo.reset);
              },
              child: const Text('체험 데이터 처음으로 되돌리기'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({
    required this.number,
    required this.title,
    required this.detail,
  });
  final String number, title, detail;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(
        radius: 14,
        backgroundColor: Colors.white,
        child: Text(
          number,
          style: const TextStyle(
            color: forest,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(fontSize: 12, color: muted)),
          ],
        ),
      ),
    ],
  );
}
