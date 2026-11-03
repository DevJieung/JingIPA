import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../domain/models.dart';
import 'app_repository.dart';
import 'local_firebase.dart';
import 'firebase_push_access.dart';
import 'push_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'startup_trace.dart';

class FirebaseRepository extends AppRepository with WidgetsBindingObserver {
  FirebaseRepository({
    this.local = false,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? call,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _db = firestore ?? FirebaseFirestore.instance,
       _testCall = call;
  final bool local;
  @override
  bool get isLocal => local;
  @override
  bool get isGuest => _auth.currentUser?.isAnonymous == true;
  @override
  Future<void> signInLocal(String actor) async {
    if (!local || !RegExp(r'^[a-f]$').hasMatch(actor)) {
      throw const LunchException('로컬 테스트 계정을 확인해 주세요.');
    }
    await _auth.signInWithEmailAndPassword(
      email: '$actor@meokkiri.test',
      password: 'lunch-local-123',
    );
  }

  @override
  Future<void> localAction(String action, {String? channelId}) async {
    if (!local) throw const LunchException('로컬 테스트에서만 사용할 수 있어요.');
    await runLocalAction(
      action,
      channelId: channelId,
      actor: _auth.currentUser?.uid,
    );
    if (action == 'reset') await _auth.signOut();
    await refresh();
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
  _testCall;
  late final _functions = FirebaseFunctions.instanceFor(
    region: 'asia-northeast3',
  );
  final List<LunchChannel> _channels = [];
  String _joinMessage = '채널에 들어왔어요.';
  @override
  String get channelJoinMessage => _joinMessage;
  final Map<String, RoundView> _views = {};
  final Map<String, List<RoundView>> _history = {};
  final Map<String, String?> _historyRoundIds = {};
  final Map<String, LoadStatus> _roundStates = {}, _historyStates = {};
  final Map<String, String> _roundErrors = {};
  final Map<String, Future<void>> _roundTasks = {};
  final Set<String> _roundAgain = {};
  final Map<String, int> _roundVersions = {};
  final Map<String, String> _roundRevisions = {};
  final Map<String, Future<void>> _historyTasks = {};
  final Map<String, DateTime> _deadlineChecks = {};
  Future<void>? _attendanceTask, _favoritesTask;
  LoadStatus _attendanceStatus = LoadStatus.idle,
      _favoritesStatus = LoadStatus.idle;
  SessionStatus _sessionStatus = SessionStatus.restoring;
  LoadStatus _channelsStatus = LoadStatus.idle;
  String? _selectedChannelId, _sessionUid;
  SharedPreferences? _preferences;
  bool _disposed = false, _initialized = false;
  final _trace = StartupTrace();
  @override
  SessionStatus get sessionStatus => _sessionStatus;
  @override
  LoadStatus get channelsStatus => _channelsStatus;
  @override
  String? get selectedChannelId => _selectedChannelId;
  @override
  LoadStatus roundStatusFor(String channelId) =>
      _roundStates[channelId] ?? LoadStatus.idle;
  @override
  String? roundErrorFor(String channelId) => _roundErrors[channelId];
  @override
  LoadStatus historyStatusFor(String channelId) =>
      _historyStates[channelId] ?? LoadStatus.idle;
  @override
  LoadStatus get attendanceStatus => _attendanceStatus;
  @override
  LoadStatus get favoritesStatus => _favoritesStatus;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  final Map<String, StreamSubscription<dynamic>> _streams = {};
  final Map<String, Timer> _retryTimers = {};
  final Map<String, int> _retryAttempts = {};
  StreamSubscription<User?>? _authStream;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _channelStream;
  Timer? _timer;
  Timer? _channelLoadTimer;
  late final _push = PushPreferences(
    access: FirebasePushAccess(),
    writeDevice: (uid, token, enabled) async {
      if (_auth.currentUser?.uid != uid) {
        throw const LunchException('계정이 변경되었어요. 다시 확인해 주세요.');
      }
      await _call('registerPushDevice', {
        'token': token,
        'enabled': enabled,
        'targetType': 'fid',
      });
    },
  );
  @override
  bool get pushNotificationsEnabled => !local && _push.enabled;
  @override
  bool get pushNotificationsBusy => !local && _push.busy;
  @override
  bool get pushNotificationsSupported => !local && _push.supported;
  @override
  bool get pushNotificationsBlocked => !local && _push.blocked;
  @override
  String? get pushNotificationsMessage => local ? null : _push.message;
  @override
  Future<void> setPushNotifications(bool enabled) async {
    if (!local) await _push.setEnabled(enabled);
  }

  @override
  Future<void> refreshPushNotifications() async {
    if (!local) await _push.refresh();
  }

  final List<StreamSubscription<dynamic>> _pushStreams = [];
  AppUser? _user;
  Duration _clockOffset = Duration.zero;
  int _authGeneration = 0;
  String? _error;
  TokenWallet _wallet = const TokenWallet();
  bool _isAdmin = false;
  final List<Restaurant> _favorites = [];
  final Map<String, Map<String, String>> _colors = {};
  @override
  TokenWallet get wallet => _wallet;
  @override
  bool get isAdmin => _isAdmin;
  @override
  List<TokenBundle> get tokenBundles => const [];
  @override
  bool get premiumActive => _views.values.any((v) => v.tokenEquipped);
  @override
  List<Restaurant> get favorites => List.unmodifiable(_favorites);
  @override
  Map<String, String> colorsFor(String id) =>
      Map.unmodifiable(_colors[id] ?? {});
  @override
  Set<String> redTargetsFor(String channelId) => colorsFor(
    channelId,
  ).entries.where((e) => e.value == 'D94B48').map((e) => e.key).toSet();
  @override
  Future<void> saveRedTargets(String channelId, Set<String> targets) =>
      saveColors(channelId, {for (final id in targets) id: 'D94B48'});
  @override
  Future<void> saveColors(String channelId, Map<String, String> colors) async {
    final response = await _call('setRedTargets', {
      'channelId': channelId,
      'colors': colors,
    });
    _colors[channelId] = Map<String, String>.from(response['colors'] as Map);
    await refresh();
  }

  @override
  Future<void> equipToken(String channelId, bool enabled) async {
    throw const LunchException('현재 버전에서는 제공하지 않는 기능이에요.');
  }

  @override
  Future<void> sendCustomerMessage(String message, String requestId) async {
    await _call('sendCustomerMessage', {
      'message': message,
      'requestId': requestId,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> customerMessages({
    bool admin = false,
  }) async {
    final result = await _call('getCustomerMessages', {'admin': admin});
    return (result['messages'] as List)
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
  }

  @override
  Future<void> purchaseTokens(String bundleId) async {
    throw const LunchException('현재 버전에서는 제공하지 않는 기능이에요.');
  }

  @override
  Future<void> setFavorite(Restaurant restaurant, bool saved) async {
    await loadFavorites();
    final generation = _authGeneration;
    await _call('setFavorite', {'restaurantId': restaurant.id, 'saved': saved});
    if (generation != _authGeneration || _disposed) return;
    _favorites.removeWhere((r) => r.id == restaurant.id);
    if (saved) _favorites.add(restaurant);
    notifyListeners();
  }

  @override
  Future<Restaurant> addManualRestaurant(
    String name,
    String address,
    String category, {
    bool report = false,
    bool saveToFavorites = true,
  }) async {
    final response = await _call('addManualRestaurant', {
      'name': name,
      'address': address,
      'category': category,
      'report': report,
      'saveToFavorites': saveToFavorites,
    });
    final r = Restaurant.fromJson(
      Map<String, dynamic>.from(response['restaurant'] as Map),
    );
    if (saveToFavorites) {
      _favorites.removeWhere((v) => v.id == r.id);
      _favorites.add(r);
    }
    notifyListeners();
    return r;
  }

  @override
  Future<void> reportRestaurant(
    String name,
    String address,
    String category, {
    String note = '',
  }) async {
    await _call('addManualRestaurant', {
      'name': name,
      'address': address,
      'category': category,
      'report': true,
      'reportOnly': true,
      'note': note.trim().isEmpty ? '검색 누락 식당 제보' : note,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> restaurantReports({
    bool admin = false,
  }) async {
    final response = await _call('getRestaurantReports', {'admin': admin});
    return (response['reports'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  @override
  Future<void> resolveReport(Map<String, dynamic> data) async {
    await _call('resolveRestaurantReport', data);
  }

  @override
  AppUser? get user => _user;
  @override
  List<LunchChannel> get channels => List.unmodifiable(_channels);
  @override
  bool get isDemo => false;
  @override
  DateTime get now => DateTime.now().add(_clockOffset);
  @override
  String? get connectionError => _error;
  @override
  RoundView? roundFor(String id) => _views[id];
  @override
  List<RoundView> roundHistoryFor(String channelId) =>
      _history[channelId] ?? const [];
  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _trace.mark('repository');
    if (!local) {
      _push.addListener(notifyListeners);
    }
    WidgetsBinding.instance.addObserver(this);
    if (!local) {
      _pushStreams.add(
        FirebaseMessaging.onMessage.listen((_) => unawaited(refresh())),
      );
      _pushStreams.add(
        FirebaseMessaging.onMessageOpenedApp.listen(
          (_) => unawaited(refresh()),
        ),
      );
      _pushStreams.add(
        FirebaseMessaging.instance.onRegistered.listen((token) async {
          try {
            await _push.registered(token);
          } catch (_) {
            /* The next login or notification setup retries registration. */
          }
        }),
      );
    }
    _authStream = _auth.userChanges().listen(
      _onAuth,
      onError: (_) {
        _sessionStatus = SessionStatus.failed;
        _error = '로그인 상태를 확인하지 못했어요.';
        notifyListeners();
      },
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final id = _selectedChannelId;
      final v = _views[id];
      if (id == null || v == null) return;
      if (v.phase == RoundPhase.submission || v.phase == RoundPhase.adjusting) {
        notifyListeners();
        final cutoff = v.phase == RoundPhase.submission ? v.revealAt : v.endsAt;
        if (!v.manualControl &&
            !now.isBefore(cutoff) &&
            now.difference(_deadlineChecks[id] ?? DateTime(2000)).inSeconds >=
                8) {
          _deadlineChecks[id] = now;
          unawaited(_refreshRound(id));
        }
      }
    });
  }

  Future<void> _readProfile(User firebaseUser, int generation) async {
    final p = await _db.doc('users/${firebaseUser.uid}').get();
    if (generation != _authGeneration || _disposed) return;
    // A cache miss is not proof of a new account while offline.
    if (!p.exists && p.metadata.isFromCache) {
      throw const LunchException('계정 정보를 확인하려면 연결이 필요해요.');
    }
    _user = AppUser(
      firebaseUser.uid,
      p.data()?['displayName'] as String? ?? '',
      emoji: p.data()?['emoji'] as String? ?? '🐘',
    );
    _sessionStatus = _user!.name.isEmpty
        ? SessionStatus.needsProfile
        : SessionStatus.ready;
    _trace.mark('profile');
  }

  Future<void> _readAdmin(User firebaseUser, int generation) async {
    try {
      final token = await firebaseUser.getIdTokenResult();
      if (generation != _authGeneration || _disposed) return;
      _isAdmin = token.claims?['admin'] == true;
      notifyListeners();
    } catch (_) {
      /* Admin actions still require server authorization. */
    }
  }

  Future<void> _onAuth(User? firebaseUser) async {
    if (_disposed) return;
    if (firebaseUser != null &&
        firebaseUser.uid == _sessionUid &&
        _user != null) {
      final generation = _authGeneration;
      try {
        await _readProfile(firebaseUser, generation);
        unawaited(_readAdmin(firebaseUser, generation));
      } catch (_) {
        /* Keep the current profile during a same-account refresh. */
      }
      notifyListeners();
      return;
    }
    final generation = ++_authGeneration;
    _trace.mark('auth');
    _sessionUid = firebaseUser?.uid;
    final oldChannelStream = _channelStream;
    _channelLoadTimer?.cancel();
    _channelStream = null;
    final oldStreams = _streams.values.toList();
    _streams.clear();
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _retryAttempts.clear();
    _user = null;
    _channels.clear();
    _views.clear();
    _history.clear();
    _historyRoundIds.clear();
    _roundStates.clear();
    _roundErrors.clear();
    _roundVersions.clear();
    _roundRevisions.clear();
    _roundTasks.clear();
    _roundAgain.clear();
    _historyTasks.clear();
    _historyStates.clear();
    _deadlineChecks.clear();
    _colors.clear();
    _favorites.clear();
    _attendance = const Attendance();
    _attendanceTask = _favoritesTask = null;
    _attendanceStatus = _favoritesStatus = LoadStatus.idle;
    _wallet = const TokenWallet();
    _isAdmin = false;
    _selectedChannelId = null;
    _clockOffset = Duration.zero;
    _error = null;
    _channelsStatus = firebaseUser == null
        ? LoadStatus.idle
        : LoadStatus.loading;
    _sessionStatus = firebaseUser == null
        ? SessionStatus.signedOut
        : SessionStatus.loadingProfile;
    if (!local) unawaited(_push.bind(null));
    notifyListeners();
    await oldChannelStream?.cancel();
    for (final stream in oldStreams) {
      await stream.cancel();
    }
    if (generation != _authGeneration || _disposed || firebaseUser == null) {
      return;
    }
    try {
      await Future.wait([
        _readProfile(firebaseUser, generation),
        SharedPreferences.getInstance()
            .then((p) {
              if (generation == _authGeneration && !_disposed) {
                _preferences = p;
                _selectedChannelId = p.getString(
                  'selected-channel-${firebaseUser.uid}',
                );
              }
            })
            .catchError((_) {
              /* Selection persistence is optional. */
            }),
      ]);
      if (generation != _authGeneration || _disposed) return;
      if (!local) unawaited(_push.bind(firebaseUser.uid));
      unawaited(_readAdmin(firebaseUser, generation));
      notifyListeners();
      _listenChannels(firebaseUser.uid, generation);
    } catch (_) {
      if (generation != _authGeneration || _disposed) return;
      _sessionStatus = SessionStatus.failed;
      _error = '계정 정보를 불러오지 못했어요. 연결을 확인해 주세요.';
      notifyListeners();
    }
  }

  void _listenChannels(String uid, int generation) {
    _channelLoadTimer?.cancel();
    _channelLoadTimer = Timer(const Duration(seconds: 12), () {
      if (generation != _authGeneration ||
          _disposed ||
          _channelsStatus != LoadStatus.loading) {
        return;
      }
      _channelsStatus = LoadStatus.failed;
      _error = '모임 연결이 오래 걸리고 있어요. 연결을 확인하고 다시 시도해 주세요.';
      notifyListeners();
    });
    _channelStream = _db
        .collection('channels')
        .where('memberIds', arrayContains: uid)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            if (generation != _authGeneration || _disposed) return;
            if (snapshot.metadata.isFromCache &&
                _channelsStatus != LoadStatus.ready) {
              // Incomplete cached membership must not select a different group or show an empty state.
              return;
            }
            final previous = {for (final c in _channels) c.id: c};
            _channelLoadTimer?.cancel();
            final ids = snapshot.docs.map((d) => d.id).toSet();
            for (final id in previous.keys.where((id) => !ids.contains(id))) {
              final view = _views.remove(id);
              if (view != null) {
                _stopSubscription(view.id);
                _stopSubscription('meta-${view.id}');
              }
              _history.remove(id);
              _historyRoundIds.remove(id);
              _roundStates.remove(id);
              _roundErrors.remove(id);
              _historyStates.remove(id);
            }
            _channels
              ..clear()
              ..addAll(
                snapshot.docs.map(
                  (d) => LunchChannel.fromJson({...d.data(), 'id': d.id}),
                ),
              );
            _channelsStatus = LoadStatus.ready;
            _error = null;
            _trace.mark('channels');
            if (!ids.contains(_selectedChannelId)) {
              _selectedChannelId = _channels.firstOrNull?.id;
            }
            for (final c in _channels) {
              if (c.roundId == null) {
                final view = _views.remove(c.id);
                if (view != null) _stopSubscription('meta-${view.id}');
                _roundStates[c.id] = LoadStatus.ready;
              } else if (_views[c.id]?.id != c.roundId) {
                _roundStates[c.id] = LoadStatus.loading;
              }
            }
            final selected = _selectedChannelId;
            if (selected != null) {
              final c = _channels.firstWhere((c) => c.id == selected);
              final old = previous[selected];
              if (c.roundId != null &&
                  (old == null ||
                      old.roundId != c.roundId ||
                      old.members.toString() != c.members.toString() ||
                      old.memberEmojis.toString() !=
                          c.memberEmojis.toString())) {
                unawaited(_refreshRound(selected));
              }
            }
            notifyListeners();
            // Secondary data cannot delay or fail the current round request.
            if (_attendanceStatus == LoadStatus.idle) {
              unawaited(loadAttendance());
            }
          },
          onError: (_) {
            if (generation != _authGeneration || _disposed) return;
            _channelLoadTimer?.cancel();
            _channelsStatus = LoadStatus.failed;
            _error = '모임을 불러오지 못했어요. 연결을 확인해 주세요.';
            notifyListeners();
          },
        );
    // One migration per session, outside the startup/refresh request chain.
    unawaited(_migrateAdmission(generation));
  }

  Future<void> _migrateAdmission(int generation) async {
    try {
      await _call('getChannelJoinRequests');
    } catch (_) {
      /* Retried explicitly on reconnect; never block the current round. */
    }
  }

  @override
  Future<void> retrySession() async {
    final current = _auth.currentUser;
    if (_sessionStatus == SessionStatus.failed || _user == null) {
      await _onAuth(current);
    } else if (_channelsStatus == LoadStatus.failed) {
      await _channelStream?.cancel();
      _channelsStatus = LoadStatus.loading;
      notifyListeners();
      _listenChannels(current!.uid, _authGeneration);
    } else {
      await refresh();
    }
  }

  @override
  Future<void> selectChannel(String channelId) async {
    if (!_channels.any((c) => c.id == channelId)) return;
    final uid = _sessionUid;
    _selectedChannelId = channelId;
    notifyListeners();
    unawaited(_refreshRound(channelId));
    try {
      await _preferences?.setString('selected-channel-$uid', channelId);
    } catch (_) {
      /* The selection still works for this session. */
    }
  }

  @override
  Future<void> loadChannelSummaries() async {
    // Two at a time keeps a large group list from flooding callable requests.
    final pending = channels
        .where((c) => c.roundId != null && c.id != _selectedChannelId)
        .toList();
    for (var start = 0; start < pending.length; start += 2) {
      await Future.wait(
        pending.skip(start).take(2).map((c) => _refreshRound(c.id)),
      );
    }
  }

  Future<Map<String, dynamic>> _call(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    try {
      if (_testCall != null) return await _testCall(name, data ?? {});
      final result = await _functions.httpsCallable(name).call(data ?? {});
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      if (details is Map &&
          details['reason'] == 'round-cooldown' &&
          details['nextRoundAt'] is num &&
          details['serverNow'] is num) {
        final serverNow = DateTime.fromMillisecondsSinceEpoch(
          (details['serverNow'] as num).toInt(),
        );
        _clockOffset = serverNow.difference(DateTime.now());
        throw RoundCooldownException(
          DateTime.fromMillisecondsSinceEpoch(
            (details['nextRoundAt'] as num).toInt(),
          ),
          serverNow,
        );
      }
      throw LunchException(e.message ?? '요청을 처리하지 못했어요.');
    }
  }

  void _stopSubscription(String key) {
    _retryTimers.remove(key)?.cancel();
    _retryAttempts.remove(key);
    unawaited(_streams.remove(key)?.cancel());
  }

  void _retrySubscription(String channelId, String key) {
    unawaited(_streams.remove(key)?.cancel());
    _retryTimers.remove(key)?.cancel();
    final generation = _authGeneration;
    final attempt = (_retryAttempts[key] ?? 0) + 1;
    _retryAttempts[key] = attempt;
    final seconds = (1 << (attempt - 1).clamp(0, 3));
    _retryTimers[key] = Timer(Duration(seconds: seconds), () {
      _retryTimers.remove(key);
      if (generation == _authGeneration &&
          channels.any((channel) => channel.id == channelId)) {
        unawaited(_refreshRound(channelId));
      }
    });
  }

  void _accept(String channelId, Map<String, dynamic> response) {
    if (!channels.any((c) => c.id == channelId)) return;
    if (response['wallet'] != null) {
      _wallet = TokenWallet.fromJson(
        Map<String, dynamic>.from(response['wallet'] as Map),
      );
    }
    _colors[channelId] = Map<String, String>.from(
      response['colorTargets'] as Map? ?? {},
    );
    if (response['serverNow'] != null) {
      _clockOffset = DateTime.fromMillisecondsSinceEpoch(
        (response['serverNow'] as num).toInt(),
      ).difference(DateTime.now());
    }
    _roundVersions[channelId] = (_roundVersions[channelId] ?? 0) + 1;
    _roundStates[channelId] = LoadStatus.ready;
    _roundErrors.remove(channelId);
    if (response['revision'] is String) {
      _roundRevisions[channelId] = response['revision'] as String;
    }
    final raw = response['round'];
    if (raw == null) {
      _views.remove(channelId);
      return;
    }
    final view = RoundView.fromJson(Map<String, dynamic>.from(raw as Map));
    if (response['history'] != null) {
      _history[channelId] = [
        for (final row in response['history'] as List)
          RoundView.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
      _historyRoundIds[channelId] = view.id;
      _historyStates[channelId] = LoadStatus.ready;
    }
    final old = _views[channelId];
    if (old != null &&
        old.id != view.id &&
        _historyRoundIds[channelId] != view.id) {
      _history.remove(channelId);
      _historyTasks.remove(channelId);
      _historyStates[channelId] = LoadStatus.idle;
    }
    if (old != null &&
        old.phase != view.phase &&
        view.phase == RoundPhase.finalized) {
      unawaited(loadAttendance(force: true));
    }
    if (old != null && old.id != view.id) {
      _stopSubscription(old.id);
      _stopSubscription('meta-${old.id}');
    }
    if (view.phase != RoundPhase.adjusting) {
      _stopSubscription(view.id);
    }
    _views[channelId] = view;
    final generation = _authGeneration;
    if (!_streams.containsKey('meta-${view.id}') &&
        !_retryTimers.containsKey('meta-${view.id}')) {
      _streams['meta-${view.id}'] = _db
          .doc('rounds/${view.id}')
          .snapshots(includeMetadataChanges: true)
          .listen(
            (snapshot) {
              if (generation != _authGeneration ||
                  _disposed ||
                  snapshot.metadata.isFromCache) {
                return;
              }
              _retryAttempts.remove('meta-${view.id}');
              if (snapshot.data()?['revision'] != null &&
                  snapshot.data()?['revision'] == _roundRevisions[channelId]) {
                return;
              }
              unawaited(_refreshRound(channelId));
            },
            onError: (_) {
              if (generation != _authGeneration || _disposed) return;
              _roundErrors[channelId] = '라운드 연결이 끊겼어요. 다시 시도해 주세요.';
              _retrySubscription(channelId, 'meta-${view.id}');
              notifyListeners();
            },
          );
    }
    if (view.phase == RoundPhase.adjusting &&
        !_streams.containsKey(view.id) &&
        !_retryTimers.containsKey(view.id)) {
      _streams[view.id] = _db
          .doc('rounds/${view.id}/results/aggregate')
          .snapshots()
          .listen(
            (_) {
              if (generation != _authGeneration || _disposed) return;
              _retryAttempts.remove(view.id);
              unawaited(_refreshRound(channelId));
            },
            onError: (_) {
              if (generation != _authGeneration || _disposed) return;
              _retrySubscription(channelId, view.id);
            },
          );
    }
  }

  Future<void> _refreshRound(String channelId) {
    if (_disposed || user == null) return Future.value();
    final running = _roundTasks[channelId];
    if (running != null) {
      _roundAgain.add(channelId);
      return running;
    }
    final generation = _authGeneration;
    late final Future<void> task;
    task = _fetchRound(channelId, generation).whenComplete(() {
      if (generation != _authGeneration ||
          _disposed ||
          _roundTasks[channelId] != task) {
        return;
      }
      _roundTasks.remove(channelId);
      if (_roundAgain.remove(channelId)) unawaited(_refreshRound(channelId));
    });
    _roundTasks[channelId] = task;
    return task;
  }

  Future<void> _fetchRound(String channelId, int generation) async {
    final channel = _channels.where((c) => c.id == channelId).firstOrNull;
    if (channel == null) return;
    if (channel.roundId == null) {
      _views.remove(channelId);
      _roundStates[channelId] = LoadStatus.ready;
      notifyListeners();
      return;
    }
    final version = _roundVersions[channelId] ?? 0;
    if (_views[channelId]?.id != channel.roundId) {
      _roundStates[channelId] = LoadStatus.loading;
    }
    try {
      final response = await _call('getRoundView', {
        'channelId': channelId,
        'includeHistory': false,
        'lean': true,
      });
      if (generation != _authGeneration ||
          _disposed ||
          !_channels.any(
            (c) => c.id == channelId && c.roundId == channel.roundId,
          )) {
        return;
      }
      if (version != (_roundVersions[channelId] ?? 0)) {
        _roundAgain.add(channelId);
        return;
      }
      _accept(channelId, response);
      if (channelId == _selectedChannelId) _trace.mark('current-round');
    } catch (_) {
      if (generation != _authGeneration || _disposed) return;
      _roundStates[channelId] = LoadStatus.failed;
      _roundErrors[channelId] = '팟 정보를 불러오지 못했어요. 다시 시도해 주세요.';
    } finally {
      if (generation == _authGeneration) notifyListeners();
    }
  }

  @override
  Future<void> refresh() async {
    if (user == null) return;
    if (_channelsStatus == LoadStatus.failed) {
      await retrySession();
      return;
    }
    final id = _selectedChannelId;
    await Future.wait([
      if (id != null) _refreshRound(id),
      loadAttendance(force: true),
      if (_favoritesStatus != LoadStatus.idle) loadFavorites(force: true),
    ]);
  }

  @override
  Future<void> loadAttendance({bool force = false}) {
    if (user == null || _disposed) return Future.value();
    if (_attendanceTask != null) return _attendanceTask!;
    if (!force && _attendanceStatus == LoadStatus.ready) return Future.value();
    final generation = _authGeneration;
    _attendanceStatus = LoadStatus.loading;
    scheduleMicrotask(notifyListeners);
    late final Future<void> task;
    task = () async {
      try {
        final response = await _call('getAttendance');
        if (generation != _authGeneration || _disposed) return;
        _attendance = Attendance.fromJson(response);
        _attendanceStatus = LoadStatus.ready;
      } catch (_) {
        if (generation == _authGeneration && !_disposed) {
          _attendanceStatus = LoadStatus.failed;
        }
      } finally {
        if (generation == _authGeneration && !_disposed) {
          _attendanceTask = null;
          notifyListeners();
        }
      }
    }();
    _attendanceTask = task;
    return task;
  }

  @override
  Future<void> loadFavorites({bool force = false}) {
    if (user == null || _disposed) return Future.value();
    if (_favoritesTask != null) return _favoritesTask!;
    if (!force && _favoritesStatus == LoadStatus.ready) return Future.value();
    final generation = _authGeneration;
    _favoritesStatus = LoadStatus.loading;
    scheduleMicrotask(notifyListeners);
    final task = () async {
      try {
        final response = await _call('getFavorites');
        if (generation != _authGeneration || _disposed) return;
        _favorites
          ..clear()
          ..addAll(
            (response['restaurants'] as List).map(
              (r) => Restaurant.fromJson(Map<String, dynamic>.from(r as Map)),
            ),
          );
        _favoritesStatus = LoadStatus.ready;
      } catch (_) {
        if (generation == _authGeneration && !_disposed) {
          _favoritesStatus = LoadStatus.failed;
        }
      } finally {
        if (generation == _authGeneration && !_disposed) {
          _favoritesTask = null;
          notifyListeners();
        }
      }
    }();
    _favoritesTask = task;
    return task;
  }

  @override
  Future<void> loadHistory(String channelId, {bool force = false}) {
    if (user == null || _disposed) return Future.value();
    if (_historyTasks[channelId] != null) return _historyTasks[channelId]!;
    if (!force && historyStatusFor(channelId) == LoadStatus.ready) {
      return Future.value();
    }
    final generation = _authGeneration;
    final channel = _channels.where((c) => c.id == channelId).firstOrNull;
    if (channel == null) return Future.value();
    final roundId = channel.roundId;
    _historyStates[channelId] = LoadStatus.loading;
    scheduleMicrotask(notifyListeners);
    late final Future<void> task;
    task = () async {
      try {
        final response = await _call('getRoundView', {
          'channelId': channelId,
          'includeHistory': true,
          'lean': true,
        });
        if (generation != _authGeneration ||
            _disposed ||
            !_channels.any((c) => c.id == channelId && c.roundId == roundId)) {
          return;
        }
        // History responses must not overwrite a newer live round or selection.
        _history[channelId] = [
          for (final row in response['history'] as List? ?? [])
            RoundView.fromJson(Map<String, dynamic>.from(row as Map)),
        ];
        _historyRoundIds[channelId] = roundId;
        _historyStates[channelId] = LoadStatus.ready;
      } catch (_) {
        if (generation == _authGeneration &&
            !_disposed &&
            _historyTasks[channelId] == task) {
          _historyStates[channelId] = LoadStatus.failed;
        }
      } finally {
        if (generation == _authGeneration &&
            !_disposed &&
            _historyTasks[channelId] == task) {
          _historyTasks.remove(channelId);
          notifyListeners();
        }
      }
    }();
    _historyTasks[channelId] = task;
    return task;
  }

  @override
  Future<void> enterDemo() async =>
      throw const LunchException('로그인을 먼저 해 주세요.');
  @override
  Future<void> signInGuest(String name, String code) async {
    final trimmedName = name.trim();
    final trimmedCode = code.trim();
    if (trimmedName.isEmpty ||
        trimmedName.length > 20 ||
        trimmedCode.isEmpty ||
        trimmedCode.length > 32) {
      throw const LunchException('이름과 초대 코드를 확인해 주세요.');
    }
    if (_auth.currentUser != null && !isGuest) {
      throw const LunchException('이미 로그인한 계정으로 초대에 참여해 주세요.');
    }
    try {
      if (_auth.currentUser == null) await _auth.signInAnonymously();
      await updateName(trimmedName);
      await joinChannel(trimmedCode);
      await _onAuth(_auth.currentUser);
    } on FirebaseAuthException catch (e) {
      throw LunchException(
        e.code == 'operation-not-allowed'
            ? '비회원 참여가 아직 준비되지 않았어요. 잠시 후 다시 시도해 주세요.'
            : '비회원 참여를 시작하지 못했어요. 연결을 확인해 주세요.',
      );
    }
  }

  Future<void> _completeSignIn(
    UserCredential result, {
    required bool linking,
  }) async {
    if (linking) {
      await result.user?.getIdToken(true);
      await _onAuth(_auth.currentUser);
    }
  }

  LunchException _signInError(FirebaseAuthException error) => LunchException(
    isGuest &&
            [
              'credential-already-in-use',
              'email-already-in-use',
              'account-exists-with-different-credential',
            ].contains(error.code)
        ? '이미 가입된 계정이에요. 다른 계정을 연결하거나 라운드를 마친 뒤 기존 계정으로 로그인해 주세요. 비회원 참여 기록은 그대로 유지돼요.'
        : error.message ?? '로그인을 완료하지 못했어요.',
  );

  @override
  Future<void> signInGoogle() async {
    try {
      final guest = isGuest ? _auth.currentUser : null;
      if (kIsWeb) {
        final result = guest != null
            ? await guest.linkWithPopup(GoogleAuthProvider())
            : await _auth.signInWithPopup(GoogleAuthProvider());
        await _completeSignIn(result, linking: guest != null);
      } else {
        const clientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
        await GoogleSignIn.instance.initialize(
          serverClientId: clientId.isEmpty ? null : clientId,
          clientId: defaultTargetPlatform == TargetPlatform.iOS
              ? const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID')
              : null,
        );
        final account = await GoogleSignIn.instance.authenticate();
        final credential = GoogleAuthProvider.credential(
          idToken: account.authentication.idToken,
        );
        final result = guest != null
            ? await guest.linkWithCredential(credential)
            : await _auth.signInWithCredential(credential);
        await _completeSignIn(result, linking: guest != null);
      }
    } on FirebaseAuthException catch (e) {
      throw _signInError(e);
    }
  }

  @override
  Future<void> signInApple() async {
    try {
      final guest = isGuest ? _auth.currentUser : null;
      late final UserCredential result;
      if (kIsWeb) {
        result = guest != null
            ? await guest.linkWithPopup(AppleAuthProvider())
            : await _auth.signInWithPopup(AppleAuthProvider());
      } else {
        result = guest != null
            ? await guest.linkWithProvider(AppleAuthProvider())
            : await _auth.signInWithProvider(AppleAuthProvider());
      }
      await _completeSignIn(result, linking: guest != null);
    } on FirebaseAuthException catch (e) {
      throw _signInError(e);
    }
  }

  @override
  Future<void> signOut() async {
    if (isGuest &&
        _views.values.any(
          (round) =>
              [
                RoundPhase.submission,
                RoundPhase.adjusting,
              ].contains(round.phase) &&
              (round.myRestaurant != null || round.tokenEquipped),
        )) {
      throw const LunchException(
        '참여 중인 라운드가 있어요. 계정을 연결하거나 라운드를 마친 뒤 나가 주세요. Round1에서는 먼저 참여를 취소할 수도 있어요.',
      );
    }
    if (!local) await _push.detach();
    await _auth.signOut();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(retryStorePurchases());
      unawaited(refreshPushNotifications());
    }
  }

  Attendance _attendance = const Attendance();
  @override
  Attendance get attendance => _attendance;
  @override
  Future<void> updateEmoji(String emoji) => updateProfile(user!.name, emoji);

  @override
  Future<void> startPodRound(
    String channelId,
    DateTime endsAt,
    List<String> expectedMemberIds,
  ) async {
    await _call('createRound', {
      'channelId': channelId,
      'endsAt': endsAt.millisecondsSinceEpoch,
      'expectedMemberIds': expectedMemberIds,
    });
    await refresh();
  }

  Future<void> _podCall(
    String action,
    String channelId,
    Map<String, dynamic> data,
  ) async {
    final generation = _authGeneration;
    final response = await _call(action, {
      'channelId': channelId,
      'roundId': roundFor(channelId)?.id,
      ...data,
    });
    if (generation != _authGeneration) return;
    _accept(channelId, response);
    notifyListeners();
  }

  @override
  Future<void> createPod(
    String channelId,
    String name,
    int minimum,
    String requestId, {
    String? restaurantId,
    String? restaurantText,
    TemporaryRestaurant? temporaryRestaurant,
  }) => _podCall('createPod', channelId, {
    'name': name,
    'minimum': minimum,
    'requestId': requestId,
    'restaurantId': restaurantId,
    'restaurantText': restaurantText,
    'temporaryRestaurant': temporaryRestaurant?.toJson(),
  });
  @override
  Future<void> joinPod(String channelId, String podId) =>
      _podCall('joinPod', channelId, {'podId': podId});
  @override
  Future<void> joinFinalPod(String channelId, String podId) =>
      _podCall('joinFinalPod', channelId, {'podId': podId});
  @override
  Future<void> leavePod(String channelId) =>
      _podCall('leavePod', channelId, {});
  @override
  Future<void> changePodDeadline(String channelId, DateTime endsAt) => _podCall(
    'setRoundCutoffs',
    channelId,
    {'endsAt': endsAt.millisecondsSinceEpoch},
  );

  @override
  Future<void> updateProfile(String name, String emoji) async {
    final generation = _authGeneration;
    await _call('registerProfile', {'name': name, 'emoji': emoji});
    if (generation != _authGeneration || _disposed) return;
    final current = _auth.currentUser;
    if (current == null) return;
    _user = AppUser(current.uid, name.trim(), emoji: emoji);
    _sessionStatus = _user!.name.isEmpty
        ? SessionStatus.needsProfile
        : SessionStatus.ready;
    notifyListeners();
  }

  @override
  Future<void> updateName(String name) =>
      updateProfile(name, user?.emoji ?? '🐘');

  @override
  Future<void> deleteAccount() async {
    await _call('deleteAccount');
    await _auth.signOut();
  }

  @override
  Future<void> createChannel(String name) async {
    await _call('createChannel', {'name': name});
  }

  @override
  Future<void> joinChannel(String code) async {
    await _call('joinChannel', {'code': code});
    _joinMessage = '채널에 들어왔어요.';
    await refresh();
  }

  @override
  Future<void> leaveChannel(String channelId) async {
    await _call('leaveChannel', {'channelId': channelId});
    _channels.removeWhere((c) => c.id == channelId);
    final view = _views.remove(channelId);
    if (view != null) {
      _stopSubscription(view.id);
      _stopSubscription('meta-${view.id}');
    }
    _colors.remove(channelId);
    await refresh();
    notifyListeners();
  }

  @override
  Future<void> removeChannelMember(String channelId, String memberId) async {
    await _call('removeChannelMember', {
      'channelId': channelId,
      'memberId': memberId,
    });
    await refresh();
  }

  @override
  Future<void> saveDefaults(String id, int minute, int duration) async {
    await _call('saveDefaults', {
      'channelId': id,
      'revealMinute': minute,
      'additionalMinutes': duration,
    });
  }

  @override
  Future<void> startRound(
    String id,
    DateTime revealAt,
    int duration, {
    List<String>? expectedMemberIds,
  }) async {
    await _call('createRound', {
      'channelId': id,
      'revealAt': revealAt.millisecondsSinceEpoch,
      'additionalMinutes': duration,
      'expectedMemberIds': ?expectedMemberIds,
    });
    await refresh();
  }

  @override
  Future<void> setRoundCutoffs(
    String channelId,
    RoundPhase expectedPhase,
    DateTime revealAt,
    DateTime endsAt,
  ) async {
    final response = await _call('setRoundCutoffs', {
      'channelId': channelId,
      'roundId': roundFor(channelId)?.id,
      'expectedPhase': expectedPhase.name,
      'revealAt': revealAt.millisecondsSinceEpoch,
      'endsAt': endsAt.millisecondsSinceEpoch,
    });
    _accept(channelId, response);
    notifyListeners();
  }

  @override
  Future<void> advanceRound(String channelId, RoundPhase expectedPhase) async {
    final response = await _call('advanceRound', {
      'channelId': channelId,
      'roundId': roundFor(channelId)?.id,
      'expectedPhase': expectedPhase.name,
    });
    _accept(channelId, response);
    notifyListeners();
  }

  @override
  Future<void> approveRoundTransition(
    String channelId,
    String transitionId,
    RoundPhase phase,
  ) async {
    final response = await _call('approveRoundTransition', {
      'channelId': channelId,
      'roundId': roundFor(channelId)?.id,
      'transitionId': transitionId,
      'approvalVersion': roundFor(channelId)?.transition?.version,
      'expectedPhase': phase.name,
    });
    _accept(channelId, response);
    notifyListeners();
  }

  @override
  Future<List<Restaurant>> search(String query, {SearchLocation? near}) async {
    final result = await _call('searchRestaurants', {
      'query': query,
      if (near != null) 'near': near.toJson(),
      'nameSearch': true,
    });
    return (result['restaurants'] as List)
        .map((e) => Restaurant.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _mutate(String action, String channelId, [String? id]) async {
    final generation = _authGeneration;
    final response = await _call(action, {
      'channelId': channelId,
      'restaurantId': ?id,
      'roundId': roundFor(channelId)?.id,
    });
    if (generation != _authGeneration) return;
    _accept(channelId, response);
    notifyListeners();
  }

  @override
  Future<void> choose(String channelId, String restaurantId) =>
      _mutate('chooseRestaurant', channelId, restaurantId);
  @override
  Future<void> joinFinalParty(String channelId, String restaurantId) =>
      _mutate('joinFinalParty', channelId, restaurantId);
  @override
  Future<void> withdraw(String channelId) =>
      _mutate('withdrawParticipation', channelId);
  @override
  Future<void> cancelRound(String channelId) =>
      _mutate('cancelRound', channelId);
  @override
  void dispose() {
    _disposed = true;
    ++_authGeneration;
    if (!local) {
      _push.removeListener(notifyListeners);
      _push.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);
    for (final stream in _pushStreams) {
      stream.cancel();
    }
    _authStream?.cancel();
    _channelStream?.cancel();
    _timer?.cancel();
    _channelLoadTimer?.cancel();
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    for (final stream in _streams.values) {
      stream.cancel();
    }
    super.dispose();
  }
}
