import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/app_repository.dart';
import '../data/location_access.dart';
import '../domain/models.dart';
import 'pod_lobby.dart';
import 'theme.dart';
import 'location_consent_dialog.dart';
import 'load_notice.dart';

String won(int value) => '${NumberFormat('#,###').format(value)}원';

Future<T?> featureSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: paper,
      builder: (_) => SafeArea(top: false, child: child),
    );

class ManualRestaurantForm extends StatefulWidget {
  const ManualRestaurantForm({
    required this.repository,
    this.initialName = '',
    this.embedded = false,
    this.selectForRound = false,
    this.showRoundFavorite = true,
    this.onSaved,
    super.key,
  });
  final AppRepository repository;
  final String initialName;
  final bool embedded;
  final bool selectForRound, showRoundFavorite;
  final ValueChanged<Restaurant>? onSaved;
  @override
  State<ManualRestaurantForm> createState() => _ManualRestaurantFormState();
}

class _ManualRestaurantFormState extends State<ManualRestaurantForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  final _address = TextEditingController(),
      _category = TextEditingController(text: '음식점');
  bool _busy = false, _report = false;
  String? _error;

  Restaurant? get _favorite => widget.repository.favorites
      .where(
        (r) =>
            r.manual &&
            r.name == _name.text.trim() &&
            r.address == _address.text.trim(),
      )
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    _name.addListener(_inputChanged);
    _address.addListener(_inputChanged);
  }

  void _inputChanged() => setState(() {});

  Future<void> _toggleFavorite() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final favorite = _favorite;
      if (favorite != null) {
        await widget.repository.setFavorite(favorite, false);
      } else {
        await widget.repository.addManualRestaurant(
          _name.text,
          _address.text,
          _category.text.trim().isEmpty ? '음식점' : _category.text,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is LunchException
              ? e.message
              : '저장하지 못했어요. 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final favorite = _favorite;
      final r =
          favorite ??
          await widget.repository.addManualRestaurant(
            _name.text,
            _address.text,
            _category.text.trim().isEmpty ? '음식점' : _category.text,
            report: _report,
            saveToFavorites: !widget.selectForRound,
          );
      if (favorite != null && _report) {
        await widget.repository.reportRestaurant(r.name, r.address, r.category);
      }
      if (mounted) {
        if (_report) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('운영자에게 식당을 제보했어요.')));
        }
        if (widget.onSaved != null) {
          widget.onSaved!(r);
        } else {
          Navigator.pop(context, r);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is LunchException
              ? e.message
              : '추가하지 못했어요. 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.embedded
      ? Column(
          children: [
            Expanded(child: _scrollingForm(context)),
            const SizedBox(height: 8),
            _submitButton(),
          ],
        )
      : _scrollingForm(context);

  Widget _submitButton() => FilledButton(
    key: const Key('save-manual-restaurant'),
    onPressed: _busy ? null : _submit,
    child: Text(
      _busy
          ? '처리 중…'
          : widget.selectForRound
          ? '직접입력한 식당 선택'
          : '내 식당에 추가',
    ),
  );

  Widget _scrollingForm(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      bottom: widget.embedded ? 0 : MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SafeArea(
      top: false,
      bottom: !widget.embedded,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          widget.embedded ? 0 : 24,
          6,
          widget.embedded ? 0 : 24,
          24,
        ),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.selectForRound ? '식당 직접입력' : '나만의 식당 직접추가',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                widget.selectForRound
                    ? '동료와 식당 이름·위치를 똑같이 입력하면 같은 식당으로 모여요.'
                    : '구내식당 등 자주 가는 장소를 저장해요. 동료와 함께 고르려면 이름·위치를 똑같이 입력해 주세요.',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              TextFormField(
                key: const Key('manual-name'),
                controller: _name,
                enabled: !_busy,
                maxLength: 80,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '식당 이름 · 지점',
                  counterText: '',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '식당 이름을 입력해 주세요.' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const Key('manual-address'),
                controller: _address,
                enabled: !_busy,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: '위치 · 주소 (예: 본관 3층)',
                  counterText: '',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '위치나 주소를 입력해 주세요.' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const Key('manual-category'),
                controller: _category,
                enabled: !_busy,
                maxLength: 40,
                decoration: InputDecoration(
                  labelText: '음식 종류 (선택 · 참고용)',
                  counterText: '',
                  suffixIcon: widget.selectForRound && widget.showRoundFavorite
                      ? IconButton(
                          key: const Key('manual-favorite-toggle'),
                          tooltip: _favorite == null ? '내 식당에 저장' : '내 식당에서 삭제',
                          isSelected: _favorite != null,
                          icon: const Icon(
                            Icons.favorite_border_rounded,
                            color: muted,
                          ),
                          selectedIcon: const Icon(
                            Icons.favorite_rounded,
                            color: orange,
                          ),
                          onPressed: _busy ? null : _toggleFavorite,
                        )
                      : null,
                ),
              ),
              if (widget.selectForRound && widget.showRoundFavorite)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    '하트를 누르면 내 식당에 저장하거나 삭제할 수 있어요.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 14),
              CheckboxListTile(
                key: const Key('report-restaurant-checkbox'),
                value: _report,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _report = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('운영자에게도 제보하기'),
                subtitle: const Text(
                  '선택 사항 · 운영자가 검토한 뒤 공용 식당 DB 등록 여부를 결정해요.',
                ),
              ),
              const SizedBox(height: 14),
              if (!widget.embedded) _submitButton(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class RestaurantTile extends StatefulWidget {
  const RestaurantTile({
    required this.restaurant,
    required this.repository,
    this.onTap,
    this.showFavorite = true,
    super.key,
  });
  final Restaurant restaurant;
  final AppRepository repository;
  final VoidCallback? onTap;
  final bool showFavorite;
  @override
  State<RestaurantTile> createState() => _RestaurantTileState();
}

class _RestaurantTileState extends State<RestaurantTile> {
  bool _saving = false;
  Restaurant get restaurant => widget.restaurant;
  AppRepository get repository => widget.repository;
  VoidCallback? get onTap => widget.onTap;
  bool get showFavorite => widget.showFavorite;

  Future<void> _toggleFavorite() async {
    if (_saving) return;
    final save = !repository.isFavorite(restaurant.id);
    setState(() => _saving = true);
    try {
      await repository.setFavorite(restaurant, save);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
            content: Text(save ? '내 식당에 저장했어요.' : '내 식당에서 삭제했어요.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
            content: Text(
              error is LunchException
                  ? error.message
                  : '저장하지 못했어요. 다시 시도해 주세요.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Surface(
    key: Key('restaurant-card-${restaurant.id}'),
    padding: EdgeInsets.zero,
    child: Semantics(
      button: onTap != null,
      child: InkWell(
        key: Key('search-result-${restaurant.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: peachSurface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  restaurant.emoji,
                  style: const TextStyle(fontSize: 25),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${restaurant.distanceMeters == null
                          ? ''
                          : restaurant.distanceMeters! < 1000
                          ? '약 ${restaurant.distanceMeters!.round()}m · '
                          : '약 ${(restaurant.distanceMeters! / 1000).toStringAsFixed(1)}km · '}${restaurant.manual ? '직접 입력 · ' : ''}${restaurant.category}\n${restaurant.address}',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              if (showFavorite) ...[
                const SizedBox(width: 4),
                IconButton(
                  key: Key('favorite-${restaurant.id}'),
                  tooltip: repository.isFavorite(restaurant.id)
                      ? '좋아하는 식당에서 삭제'
                      : '좋아하는 식당에 저장',
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            semanticsLabel: '저장 중',
                          ),
                        )
                      : Icon(
                          repository.isFavorite(restaurant.id)
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: repository.isFavorite(restaurant.id)
                              ? orange
                              : muted,
                        ),
                  onPressed: _saving ? null : _toggleFavorite,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class SearchSheet extends StatefulWidget {
  const SearchSheet({
    required this.repository,
    this.allowManual = false,
    this.showFavorites = false,
    this.addToFavorites = false,
    this.manualFavorite = false,
    this.locationAccess = const LocationAccess(),
    this.onTemporaryRestaurant,
    super.key,
  });
  final AppRepository repository;
  final bool allowManual;
  final ValueChanged<TemporaryRestaurant>? onTemporaryRestaurant;
  final bool showFavorites;
  final bool addToFavorites, manualFavorite;
  final LocationAccess locationAccess;
  @override
  State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  late final _tabs = TabController(
    length: 1 + (widget.showFavorites ? 1 : 0) + (widget.allowManual ? 1 : 0),
    initialIndex: _initialTab,
    vsync: this,
  );
  Timer? _debounce;
  List<Restaurant> _results = [];
  SearchLocation? _near;
  LocationFailure? _locationFailure;
  bool _loading = false, _locating = false;
  bool _distanceAttempted = false;
  String? _error;
  // Query and location of the results on screen, to skip repeating a search.
  String? _shownQuery;
  SearchLocation? _shownNear;
  int _generation = 0, _locationGeneration = 0;
  late int _tab = _initialTab;
  int get _initialTab =>
      widget.showFavorites && widget.repository.favorites.isNotEmpty
      ? 1 + (widget.allowManual ? 1 : 0)
      : 0;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_tabChanged);
    unawaited(widget.repository.loadFavorites());
  }

  void _tabChanged() {
    if (_tab == _tabs.index) return;
    FocusScope.of(context).unfocus();
    setState(() => _tab = _tabs.index);
  }

  static String _searchKey(String query) =>
      query.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// Typing searches only complete words of 2+ characters. Each server search
  /// reads up to 200 restaurants, and a single syllable or a Hangul consonant
  /// being composed (e.g. `만ㄷ`) matches thousands. Submitting still searches.
  static bool _autoSearchable(String key) {
    final runes = key.runes.toList();
    if (runes.length < 2) return false;
    final last = runes.last;
    return !(last >= 0x3131 && last <= 0x318E) &&
        !(last >= 0x1100 && last <= 0x11FF);
  }

  Future<void> _load(String query, {bool auto = false}) async {
    final generation = ++_generation;
    final key = _searchKey(query);
    if (key.isEmpty || (auto && !_autoSearchable(key))) {
      setState(() {
        _results = [];
        _shownQuery = null;
        _loading = false;
        _error = null;
      });
      return;
    }
    if (key == _shownQuery &&
        identical(_near, _shownNear) &&
        _error == null &&
        !_loading) {
      return; // e.g. pressing search right after the typing search finished
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final near = _near;
      final rows = await widget.repository.search(query, near: near);
      if (mounted && generation == _generation) {
        setState(() {
          _results = rows;
          _shownQuery = key;
          _shownNear = near;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '검색 결과를 불러오지 못했어요. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
    if (mounted &&
        generation == _generation &&
        !_distanceAttempted &&
        _near == null &&
        // Saved consent sorts any multi-result name search, e.g. branches of one brand.
        _results.length > 1 &&
        await widget.locationAccess.consentGranted()) {
      if (!mounted || generation != _generation) {
        return;
      }
      _distanceAttempted = true;
      await _locate(requestPermission: false);
    }
  }

  void _queryChanged(String query) {
    _debounce?.cancel();
    // Invalidate an older response as soon as the input changes.
    ++_generation;
    if (_near == null && _locating && query.trim().isNotEmpty) {
      // A pending GPS fix must not block a name search or replace its results.
      ++_locationGeneration;
      setState(() => _locating = false);
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _load(query, auto: true),
    );
  }

  void _submitSearch(String query) {
    _queryChanged(query);
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    _load(query);
  }

  Future<void> _useLocation() async {
    if (_locating) return;
    final consent = await widget.locationAccess.consentGranted();
    if (!mounted) return;
    if (!consent) {
      final agreed = await confirmLocationConsent(context);
      if (agreed != true || !mounted) return;
      await widget.locationAccess.setConsent(true);
    }
    if (mounted) await _locate(requestPermission: true);
  }

  Future<void> _locate({required bool requestPermission}) async {
    final generation = ++_locationGeneration;
    setState(() {
      _locating = true;
      _locationFailure = null;
    });
    try {
      final near = await widget.locationAccess.current(
        requestPermission: requestPermission,
      );
      if (!mounted || generation != _locationGeneration) return;
      setState(() => _near = near);
      await _load(_controller.text);
    } catch (e) {
      if (mounted && generation == _locationGeneration) {
        setState(
          () => _locationFailure = e is LocationFailure
              ? e
              : const LocationFailure('현재 위치를 확인하지 못했어요. 이름으로 검색하거나 다시 시도하세요.'),
        );
      }
    } finally {
      if (mounted && generation == _locationGeneration) {
        setState(() => _locating = false);
      }
    }
  }

  Future<void> _disableLocation() async {
    ++_locationGeneration;
    ++_generation;
    _debounce?.cancel();
    await widget.locationAccess.setConsent(false);
    if (!mounted) return;
    setState(() {
      _near = null;
      _locating = false;
      _locationFailure = null;
      _results = [];
      _shownQuery = null;
    });
    await _load(_controller.text);
  }

  @override
  void dispose() {
    ++_locationGeneration;
    _tabs.dispose();
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Widget _list() => _results.isEmpty
      ? Center(
          child: SingleChildScrollView(
            child: Text(
              _controller.text.trim().isEmpty
                  ? '식당 이름을 검색해 주세요.'
                  : _shownQuery == null
                  ? '두 글자 이상 입력하거나 검색을 눌러 주세요.'
                  : '검색된 식당이 없어요.\n운영자에게 제보하면 확인 후 등록돼요.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted),
            ),
          ),
        )
      : ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: _results.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => RestaurantTile(
            restaurant: _results[i],
            repository: widget.repository,
            showFavorite: !widget.addToFavorites,
            onTap: () => Navigator.pop(context, _results[i]),
          ),
        );

  Widget _searchPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        key: const Key('restaurant-query'),
        controller: _controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded),
          hintText: '식당 이름으로 검색',
          suffixIcon: IconButton(
            key: const Key('submit-restaurant-search'),
            tooltip: '검색',
            onPressed: () => _submitSearch(_controller.text),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ),
        onChanged: _queryChanged,
        onSubmitted: _submitSearch,
      ),
      Row(
        children: [
          Expanded(
            child: _near == null
                ? TextButton.icon(
                    key: const Key('use-nearby-location'),
                    onPressed: _locating ? null : _useLocation,
                    icon: const Icon(Icons.my_location_rounded, size: 18),
                    label: Text(_locating ? '현재 위치 확인 중…' : '검색 결과 거리순으로'),
                  )
                : const Text(
                    '검색 결과 · 가까운 순',
                    style: TextStyle(color: forest, fontSize: 12),
                  ),
          ),
          if (_near != null) ...[
            IconButton(
              key: const Key('refresh-nearby-location'),
              tooltip: '현재 위치 새로고침',
              onPressed: _locating
                  ? null
                  : () => _locate(requestPermission: false),
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
            IconButton(
              key: const Key('disable-nearby-location'),
              tooltip: '위치 사용 끄기 · 동의 철회',
              onPressed: _disableLocation,
              icon: const Icon(Icons.location_off_outlined, size: 20),
            ),
          ],
        ],
      ),
      if (_near == null &&
          _controller.text.trim().isNotEmpty &&
          !widget.repository.isDemo)
        const Text(
          '전국 이름 검색 · 위치 미사용',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      if (_locationFailure != null &&
          MediaQuery.viewInsetsOf(context).bottom == 0) ...[
        Text(
          _locationFailure!.message,
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        if (_locationFailure!.appSettings || _locationFailure!.locationSettings)
          TextButton(
            onPressed: () => _locationFailure!.appSettings
                ? widget.locationAccess.openAppSettings()
                : widget.locationAccess.openLocationSettings(),
            child: const Text('위치 설정 열기'),
          ),
      ],
      TextButton.icon(
        key: const Key('search-report-restaurant'),
        onPressed: () async {
          final temporary = await featureSheet<TemporaryRestaurant>(
            context,
            RestaurantReportForm(
              repository: widget.repository,
              allowTemporary: widget.onTemporaryRestaurant != null,
            ),
          );
          if (temporary != null && mounted) {
            widget.onTemporaryRestaurant?.call(temporary);
            Navigator.pop(context);
          }
        },
        icon: const Icon(Icons.add_location_alt_outlined, size: 18),
        label: const Text('DB에 없는 식당 제보하기'),
      ),
      Expanded(
        child: _loading || (_locating && _controller.text.trim().isEmpty)
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: TextButton(
                  onPressed: () => _load(_controller.text),
                  child: Text(_error!),
                ),
              )
            : _list(),
      ),
    ],
  );

  Widget _favoritesPanel() {
    final favorites = widget.repository.favorites
        .where((r) => !r.manual)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${favorites.length}곳 저장 · 식당을 누르면 팟 식당으로 선택해요.',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: favorites.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '아직 저장한 식당이 없어요.\n식당찾기의 하트나 내식당 관리에서 저장해 주세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted),
                        ),
                        TextButton(
                          onPressed: () => _tabs.animateTo(0),
                          child: const Text('식당 찾아보기'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  key: const Key('round-favorites-list'),
                  itemCount: favorites.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => RestaurantTile(
                    restaurant: favorites[i],
                    repository: widget.repository,
                    onTap: () => Navigator.pop(context, favorites[i]),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .87,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.addToFavorites ? '내 식당에 추가하기' : '팟 식당 선택',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '식당 선택 닫기',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 22),
                    ),
                  ],
                ),
                if (MediaQuery.viewInsetsOf(context).bottom == 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      widget.addToFavorites
                          ? '식당을 누르면 저장돼요. 주소와 지점도 확인해 주세요.'
                          : '식당을 누르면 선택돼요. 주소와 지점도 확인해 주세요.',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                if (_tabs.length > 1)
                  TabBar(
                    controller: _tabs,
                    labelPadding: EdgeInsets.zero,
                    tabs: [
                      const Tab(
                        key: Key('restaurant-tab-search'),
                        text: '식당찾기',
                      ),
                      if (widget.allowManual)
                        const Tab(
                          key: Key('add-manual-restaurant'),
                          text: '직접추가',
                        ),
                      if (widget.showFavorites)
                        const Tab(
                          key: Key('restaurant-tab-favorites'),
                          text: '내 식당',
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      _searchPanel(),
                      if (widget.allowManual)
                        ManualRestaurantForm(
                          repository: widget.repository,
                          embedded: true,
                          selectForRound: widget.showFavorites,
                          showRoundFavorite: widget.manualFavorite,
                          onSaved: (r) => Navigator.pop(context, r),
                        ),
                      if (widget.showFavorites) _favoritesPanel(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class FavoritesPanel extends StatelessWidget {
  const FavoritesPanel({required this.repository, super.key});
  final AppRepository repository;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repository,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        PageHeading(
          title: '내 식당',
          onHelp: () => featureSheet<void>(context, const TabHelpSheet(tab: 2)),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('manage-add-restaurant'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('내가 좋아하는 식당 추가하기'),
          onPressed: () async {
            final r = await featureSheet<Restaurant>(
              context,
              SearchSheet(
                repository: repository,
                addToFavorites: true,
                allowManual: false,
              ),
            );
            if (r != null) {
              try {
                await repository.setFavorite(r, true);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      margin: EdgeInsets.fromLTRB(16, 0, 16, 88),
                      content: Text('내 식당에 저장했어요.'),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            }
          },
        ),
        const SizedBox(height: 16),
        if (repository.favoritesStatus == LoadStatus.idle ||
            repository.favoritesStatus == LoadStatus.loading)
          const LoadNotice(message: '내 식당을 불러오고 있어요.'),
        if (repository.favoritesStatus == LoadStatus.failed)
          LoadNotice(
            message: '내 식당을 불러오지 못했어요.',
            failed: true,
            onRetry: () => unawaited(repository.loadFavorites(force: true)),
          ),
        if (repository.favoritesStatus == LoadStatus.ready &&
            repository.favorites.isEmpty)
          const Surface(
            child: Column(
              children: [
                ElephantArt(size: 110, scene: ElephantScene.favorite),
                SizedBox(height: 12),
                Text(
                  '자주 가는 식당을 모아두세요.\n등록된 식당을 검색해 저장할 수 있어요.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ResponsiveCards(
          children: [
            for (final r in repository.favorites)
              RestaurantTile(restaurant: r, repository: repository),
          ],
        ),
      ],
    ),
  );
}

class TutorialSheet extends StatefulWidget {
  const TutorialSheet({super.key});
  @override
  State<TutorialSheet> createState() => _TutorialSheetState();
}

class _TutorialSheetState extends State<TutorialSheet> {
  final _controller = PageController();
  int _step = 0;
  static const _steps = [
    (
      Icons.people_outline_rounded,
      '동료와 채널에 모여요',
      '채널을 만들고 초대 코드나 링크를 공유하세요.\n구성원 누구나 라운드를 열 수 있어요. 라운드를 열면 내가 라운드장이 돼요. 한 번의 모집 마감 시각을 정하면 자동으로 마감해요.',
    ),
    (
      Icons.favorite_border_rounded,
      '가고 싶은 식당 한 곳',
      '이름으로 등록된 식당을 검색해요. 등록 식당을 선택하거나 원하는 내용을 직접 입력해 팟을 만들어요.',
    ),
    (
      Icons.swap_horiz_rounded,
      '마감 전까지 마음을 바꿔도 돼요',
      '팟별 인원수를 보고 마감 전까지 참여·이동·대기할 수 있어요. 마감 때 최소 인원을 채운 팟이 성사돼요.',
    ),
    (
      Icons.workspace_premium_outlined,
      '함께 먹고 참석률을 쌓아요',
      '참석률은 마감 때 성사된 팟 참여를 기준으로 집계해요. 5회 이상·90% 이상이면 프로참석러 배지를 받아요.',
    ),
  ];
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .78,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('먹끼리 사용법', style: Theme.of(context).textTheme.titleLarge),
          Text(
            '${_step + 1} / ${_steps.length}',
            style: const TextStyle(color: muted),
          ),
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _step = i),
              children: [
                for (final step in _steps)
                  SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 28),
                        ElephantArt(
                          size: 96,
                          scene: _step == 0
                              ? ElephantScene.together
                              : _step == 1
                              ? ElephantScene.secret
                              : _step == 2
                              ? ElephantScene.together
                              : ElephantScene.favorite,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          step.$2,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 16),
                        Text(step.$3, style: const TextStyle(height: 1.9)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          FilledButton(
            key: const Key('tutorial-next'),
            onPressed: () {
              if (_step == _steps.length - 1) {
                Navigator.pop(context);
              } else {
                _controller.nextPage(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              }
            },
            child: Text(_step == _steps.length - 1 ? '시작할게요' : '다음'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    ),
  );
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    required this.repository,
    this.admin = false,
    super.key,
  });
  final AppRepository repository;
  final bool admin;
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late Future<List<Map<String, dynamic>>> _data;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = widget.repository.restaurantReports(admin: widget.admin);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.admin ? '운영자 · 식당 등록 제보' : '내 식당 제보')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(_reload),
              child: const Text('제보를 불러오지 못했어요. 다시 시도'),
            ),
          );
        }
        final rows = snapshot.data ?? [];
        return RefreshIndicator(
          onRefresh: () async {
            setState(_reload);
            await _data;
          },
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (rows.isEmpty) const Text('접수된 제보가 없어요.'),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r['name'],
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(r['address']),
                        if ((r['note'] as String? ?? '').isNotEmpty)
                          Text(
                            r['note'],
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                        const SizedBox(height: 8),
                        Tag(
                          {
                                'pending': '확인 대기',
                                'approved': 'DB 등록 완료',
                                'rejected': '등록 보류',
                              }[r['status']] ??
                              r['status'],
                        ),
                        if (r['resolutionNote'] != null)
                          Text(
                            r['resolutionNote'],
                            style: const TextStyle(fontSize: 12),
                          ),
                        if (widget.admin && r['status'] == 'pending')
                          TextButton(
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => ResolveReportScreen(
                                    repository: widget.repository,
                                    report: r,
                                  ),
                                ),
                              );
                              if (mounted) setState(_reload);
                            },
                            child: const Text('식당 확인 · DB 등록'),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class ResolveReportScreen extends StatefulWidget {
  const ResolveReportScreen({
    required this.repository,
    required this.report,
    super.key,
  });
  final AppRepository repository;
  final Map<String, dynamic> report;
  @override
  State<ResolveReportScreen> createState() => _ResolveReportScreenState();
}

class _ResolveReportScreenState extends State<ResolveReportScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.report['name']);
  late final _address = TextEditingController(text: widget.report['address']);
  late final _category = TextEditingController(text: widget.report['category']);
  final _note = TextEditingController();
  final _latitude = TextEditingController(),
      _longitude = TextEditingController();
  Restaurant? _existing;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _category.dispose();
    _note.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _resolve(bool approved) async {
    if (_busy || !_form.currentState!.validate()) return;
    final latitude = double.tryParse(_latitude.text.trim()),
        longitude = double.tryParse(_longitude.text.trim());
    if (approved &&
        _existing == null &&
        (latitude == null ||
            longitude == null ||
            !latitude.isFinite ||
            !longitude.isFinite ||
            latitude < 32 ||
            latitude > 39.5 ||
            longitude < 123.5 ||
            longitude > 132.5)) {
      setState(() => _error = '주변 검색에 사용할 식당의 위도·경도를 확인해 입력해 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.resolveReport({
        'reportId': widget.report['id'],
        'status': approved ? 'approved' : 'rejected',
        'note': _note.text,
        'name': _name.text,
        'address': _address.text,
        'category': _category.text,
        if (_existing != null) 'restaurantId': _existing!.id,
        if (approved && _existing == null) 'latitude': latitude,
        if (approved && _existing == null) 'longitude': longitude,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is LunchException
              ? e.message
              : '제보를 처리하지 못했어요. 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('식당 정보 확인')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('제보의 식당명·주소를 확인한 뒤 기존 식당에 연결하거나 공용 검색 DB에 등록하세요.'),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () async {
                    final r = await featureSheet<Restaurant>(
                      context,
                      SearchSheet(
                        repository: widget.repository,
                        allowManual: false,
                      ),
                    );
                    if (r != null && mounted) setState(() => _existing = r);
                  },
            child: Text(
              _existing == null ? '기존 DB 식당 검색 · 연결' : '연결: ${_existing!.name}',
            ),
          ),
          if (_existing != null)
            TextButton(
              onPressed: () => setState(() => _existing = null),
              child: const Text('연결 해제 · 새 식당으로 등록'),
            ),
          for (final field in [
            (_name, '확인한 식당명'),
            (_address, '확인한 주소'),
            (_category, '음식 종류'),
          ])
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: TextFormField(
                controller: field.$1,
                maxLength: field.$1 == _name
                    ? 80
                    : field.$1 == _address
                    ? 200
                    : 40,
                decoration: InputDecoration(labelText: field.$2),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? '정보를 입력해 주세요.' : null,
              ),
            ),
          const SizedBox(height: 14),
          if (_existing == null) ...[
            const Text(
              '새 식당을 주변 검색에 표시하려면 지도에서 확인한 식당 좌표를 입력하세요.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: const Key('verified-restaurant-latitude'),
              controller: _latitude,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '확인한 위도 (예: 37.57)'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: const Key('verified-restaurant-longitude'),
              controller: _longitude,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '확인한 경도 (예: 126.98)',
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextFormField(
            controller: _note,
            maxLength: 500,
            decoration: const InputDecoration(labelText: '확인 근거 · 처리 사유'),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? '확인 근거나 보류 사유를 남겨 주세요.' : null,
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : () => _resolve(true),
            child: Text(_existing == null ? '확인 완료 · DB에 등록' : '기존 식당에 연결 완료'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _resolve(false),
            child: const Text('등록 보류'),
          ),
        ],
      ),
    ),
  );
}

class PersonColorDialog extends StatefulWidget {
  const PersonColorDialog({required this.initial, super.key});
  final String initial;
  @override
  State<PersonColorDialog> createState() => _PersonColorDialogState();
}

class _PersonColorDialogState extends State<PersonColorDialog> {
  late int _value = int.parse(widget.initial, radix: 16);
  late final _code = TextEditingController(text: widget.initial);
  String? _error;
  String get _hex => _value.toRadixString(16).padLeft(6, '0').toUpperCase();
  void _change(int shift, double value) => setState(() {
    _value = (_value & ~(255 << shift)) | (value.round() << shift);
    _code.text = _hex;
    _error = null;
  });
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('원하는 색상 선택'),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_rounded,
              size: 72,
              color: Color(0xFF000000 | _value),
            ),
            for (final channel in [
              (16, 'R', Colors.red),
              (8, 'G', Colors.green),
              (0, 'B', Colors.blue),
            ])
              Row(
                children: [
                  Text(channel.$2),
                  Expanded(
                    child: Slider(
                      activeColor: channel.$3,
                      min: 0,
                      max: 255,
                      divisions: 255,
                      value: ((_value >> channel.$1) & 255).toDouble(),
                      onChanged: (v) => _change(channel.$1, v),
                    ),
                  ),
                  Text('${(_value >> channel.$1) & 255}'),
                ],
              ),
            TextField(
              key: const Key('custom-color-code'),
              controller: _code,
              maxLength: 7,
              decoration: InputDecoration(
                labelText: '색상 코드 #RRGGBB',
                errorText: _error,
              ),
              textCapitalization: TextCapitalization.characters,
              onChanged: (v) {
                final hex = v.trim().replaceFirst('#', '').toUpperCase();
                setState(() {
                  if (validPersonColor(hex)) {
                    _value = int.parse(hex, radix: 16);
                    _error = null;
                  } else {
                    _error = '6자리 색상 코드를 입력해 주세요.';
                  }
                });
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        key: const Key('apply-custom-color'),
        style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
        onPressed: _error == null ? () => Navigator.pop(context, _hex) : null,
        child: const Text('이 색상 사용'),
      ),
    ],
  );
}

class TabHelpSheet extends StatelessWidget {
  const TabHelpSheet({required this.tab, super.key});
  final int tab;
  static const _content = [
    (
      '내 모임 관리 도움말',
      [
        ('동료를 초대해요', '모임 카드에서 초대 코드와 링크를 확인해요. 모집 중에도 초대 코드나 링크로 바로 입장해요.'),
        (
          '한 번의 마감으로 모여요',
          '2명 이상 모이면 회원 누구나 라운드를 열 수 있어요. 시작할 때 현재 구성원과 마감 시각을 확인해요. 마감 전 모임 나가기·계정 삭제는 제한돼요.',
        ),
      ],
    ),
    (
      '식당 정하기 도움말',
      [
        ('모임을 바로 바꿔요', '상단의 선택한 모임 박스에서 모임 변경을 누르면 이 화면에서 다른 모임을 고를 수 있어요.'),
        (
          '빈 대기실에서 시작해요',
          '+ 팟 만들기를 누르고 팟 이름과 최소 인원(2~100명)을 정해요. 등록 식당을 선택하거나 직접 입력을 골라요. 직접 입력은 비워두어도 괜찮아요. 만든 사람도 참여해요.',
        ),
        (
          '이모지는 라운드마다 골라요',
          '라운드가 열리면 모두 코끼리로 시작해요. 대기실의 이번 라운드 내 이모지를 눌러 바꾸면 대기실과 팟 자리에 그 이모지로 보여요. 마감 전까지 바꿀 수 있고 다음 라운드는 다시 코끼리예요.',
        ),
        (
          '마감 전까지 자유롭게 옮겨요',
          '한 사람은 한 팟에 참여해요. 다른 팟에 참여하면 이전 팟에서는 자동으로 빠져요. 대기실로 돌아갔다 다시 참여할 수도 있어요.',
        ),
        (
          '내가 만든 팟은 지울 수 있어요',
          '마감 전, 내가 만든 팟 카드의 팟 삭제를 눌러요. 다른 동료가 한 명이라도 들어와 있으면 지울 수 없어요. 나 혼자 있던 팟을 지우면 대기실로 돌아가요.',
        ),
        (
          '최소 인원을 채우면 성사돼요',
          '마감 때 최소 인원 이상이면 팟이 성사되고 같은 팟 동료를 확인해요. 최소 인원 미달은 미성사로 남아요. 식당 대신 직접 입력한 내용으로 만든 팟도 같은 기준으로 성사돼요.',
        ),
        (
          '마감 후에도 함께 갈 수 있어요',
          '대기실에 남았거나 내 팟이 미성사라면 마감 때 성사된 팟 중 한 곳을 최종 선택해요. 한 번 선택하면 바꿀 수 없고, 다음 라운드가 시작되면 선택이 끝나요. 참석률은 마감 순간의 기록을 유지해요.',
        ),
        (
          '없는 식당을 임시로 넣어요',
          '팟 만들기의 식당 검색에서 DB에 없는 식당을 제보하며 임시로 넣고 제보하기 또는 그냥 제보만 하기를 골라요. 임시로 넣으면 제보가 바로 접수되고 식당 옆에 [임시]로 표시해요. 공용 DB와 내 식당에는 자동 저장하지 않아요.',
        ),
        (
          '참석률과 프로참석러',
          '시작할 때 구성원이었던 라운드 중 마감 때 성사된 팟에 속한 비율이에요. 5회 이상·90% 이상이면 프로참석러 배지를 받아요. 실제 식사 확인 기록은 아니에요.',
        ),
      ],
    ),
    (
      '내 식당 도움말',
      [
        (
          'DB에 등록된 식당을 저장해요',
          '식당 이름으로 검색해 저장해요. 위치에 동의하면 검색 결과를 가까운 순으로 볼 수 있어요.',
        ),
        (
          '없는 식당은 운영자에게 제보해요',
          '팟 만들기나 식당 검색에서 이름과 위치를 제보해요. 등록 식당 검색은 운영자 확인 후 이용할 수 있어요. 팟에는 원하는 내용을 직접 입력할 수도 있어요.',
        ),
      ],
    ),
    (
      '내 프로필 도움말',
      [
        (
          '이름을 바꿔요',
          '이름 옆 연필을 눌러 수정해요. 프로필에는 이모지가 없어요. 대기실 이모지는 식당 정하기에서 라운드마다 골라요.',
        ),
        (
          '참석률을 확인해요',
          '새 팟 방식의 마감된 라운드부터 집계해요. 취소된 라운드나 시작 뒤 들어온 라운드는 분모에서 제외돼요.',
        ),
        ('개인 설정과 문의', '위치 사용과 Push 알림을 각각 켜거나 끄세요. 고객의 소리는 본인과 운영자만 볼 수 있어요.'),
      ],
    ),
  ];
  @override
  Widget build(BuildContext context) {
    final content = _content[tab.clamp(0, 3)];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 28),
        children: [
          Text(
            content.$1,
            key: const Key('tab-help-title'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 18),
          for (final step in content.$2)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.$1,
                      style: const TextStyle(
                        color: forest,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      step.$2,
                      style: const TextStyle(fontSize: 13, height: 1.7),
                    ),
                  ],
                ),
              ),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('알겠어요'),
          ),
        ],
      ),
    );
  }
}

class CustomerMessagesScreen extends StatefulWidget {
  const CustomerMessagesScreen({
    required this.repository,
    this.admin = false,
    super.key,
  });
  final AppRepository repository;
  final bool admin;
  @override
  State<CustomerMessagesScreen> createState() => _CustomerMessagesScreenState();
}

class _CustomerMessagesScreenState extends State<CustomerMessagesScreen> {
  final _message = TextEditingController();
  String _requestId = DateTime.now().microsecondsSinceEpoch.toString();
  bool _sending = false;
  String? _error;
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final messages = await widget.repository.customerMessages(
        admin: widget.admin,
      );
      if (mounted) {
        setState(() {
          _messages = messages;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _send() async {
    final value = _message.text.trim();
    if (value.isEmpty) {
      setState(() => _error = '메시지를 입력해 주세요.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.repository.sendCustomerMessage(value, _requestId);
      if (!mounted) return;
      _message.clear();
      _requestId = DateTime.now().microsecondsSinceEpoch.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.repository.isDemo
                ? '체험용 메시지를 저장했어요. 실제 운영자에게 전송되지는 않아요.'
                : '운영자에게 메시지가 접수됐어요.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.admin ? '운영자 · 고객의 소리' : '고객의 소리'),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: '메시지 새로고침',
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          if (!widget.admin) ...[
            const Text(
              '먹끼리를 쓰며 느낀 점을 들려주세요.',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: forest,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '메시지는 본인과 운영자만 확인할 수 있어요. 비밀번호나 결제 정보는 적지 마세요.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            if (widget.repository.isDemo)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '체험 모드에서는 기기에만 저장돼요.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
            const SizedBox(height: 18),
            TextField(
              key: const Key('customer-message-input'),
              controller: _message,
              enabled: !_sending,
              minLines: 5,
              maxLines: 8,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: '운영자에게 보낼 메시지',
                hintText: '예: 식당을 고를 때 이런 점이 불편했어요.',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('send-customer-message'),
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(_sending ? '보내는 중…' : '메시지 보내기'),
            ),
            const SizedBox(height: 28),
            const Text(
              '내 보낸 메시지',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                key: const Key('customer-message-error'),
                style: const TextStyle(color: Color(0xFFD94B48)),
              ),
            ),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading && _messages.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('아직 접수된 메시지가 없어요.', style: TextStyle(color: muted)),
            ),
          for (final message in _messages)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.admin ? '${message['senderName']} · ' : ''}${DateFormat('yyyy.MM.dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch((message['createdAt'] as num).toInt()))} · 접수 완료',
                      style: const TextStyle(fontSize: 12, color: forest),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      message['message'] as String,
                      style: const TextStyle(fontSize: 13, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
