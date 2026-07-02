import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pac_service.g.dart';

@Riverpod(keepAlive: true)
PacService pacService(Ref ref) => PacService(ref: ref);

@Riverpod(keepAlive: true)
class PacStatus extends _$PacStatus with AppLogger {
  @override
  Future<bool> build() async {
    final pacService = ref.watch(pacServiceProvider);
    final pacEnabled = ref.watch(Preferences.pacEnabled);
    final connectionStatus = ref.watch(connectionNotifierProvider);
    final mixedPort = ref.watch(ConfigOptions.mixedPort);
    final customRules = ref.watch(Preferences.pacCustomRules);

    final isConnected = connectionStatus.valueOrNull?.isConnected ?? false;

    if (pacEnabled && isConnected) {
      try {
        await pacService.start(mixedPort);
        return true;
      } catch (e) {
        loggy.error("failed to start PAC service", e);
        return false;
      }
    } else {
      await pacService.stop();
      return false;
    }
  }
}

class PacService with AppLogger {
  PacService({required this.ref});

  final Ref ref;
  HttpServer? _server;
  String? _cachedPacContent;
  int? _lastMixedPort;

  bool get isRunning => _server != null;

  Future<void> start(int mixedPort) async {
    if (isRunning && _lastMixedPort == mixedPort) return;

    await stop();

    try {
      final pacUrl = ref.read(Preferences.pacUrl);
      loggy.info("downloading gfwlist from $pacUrl");

      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(pacUrl));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      final decoded = utf8.decode(base64.decode(body.trim()));
      final rules = _parseGfwlist(decoded);

      final customRules = ref.read(Preferences.pacCustomRules);
      final customParsedRules = _parseCustomRules(customRules);
      final allRules = [...customParsedRules, ...rules];

      _cachedPacContent = _generatePacContent(allRules, mixedPort);
      _lastMixedPort = mixedPort;

      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = _server!.port;
      final pacAddress = "http://127.0.0.1:$port/pac.js";

      loggy.info("PAC server started on $pacAddress");

      _server!.listen((request) {
        if (request.uri.path == '/pac.js') {
          request.response
            ..headers.contentType = ContentType("application", "x-ns-proxy-autoconfig")
            ..write(_cachedPacContent)
            ..close();
        } else {
          request.response.statusCode = 404;
          request.response.close();
        }
      });

      await _setSystemAutoProxy(pacAddress);
    } catch (e) {
      loggy.error("failed to start PAC service", e);
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      loggy.info("PAC server stopped");
    }
    await _clearSystemAutoProxy();
  }

  List<_GfwRule> _parseCustomRules(List<String> rules) {
    final parsed = <_GfwRule>[];
    for (final line in rules) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('!') || trimmed.startsWith('#')) continue;

      if (trimmed.startsWith('@@')) {
        final rule = _parseRule(trimmed.substring(2));
        if (rule != null) parsed.add(rule.copyWith(isWhitelist: true));
      } else {
        final rule = _parseRule(trimmed);
        if (rule != null) parsed.add(rule);
      }
    }
    return parsed;
  }

  List<_GfwRule> _parseGfwlist(String content) {
    final rules = <_GfwRule>[];
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('!') || trimmed.startsWith('[')) continue;

      if (trimmed.startsWith('@@')) {
        final rule = _parseRule(trimmed.substring(2));
        if (rule != null) rules.add(rule.copyWith(isWhitelist: true));
      } else {
        final rule = _parseRule(trimmed);
        if (rule != null) rules.add(rule);
      }
    }
    return rules;
  }

  _GfwRule? _parseRule(String line) {
    if (line.startsWith('||')) {
      final domain = line.substring(2).split('/').first.split(':').first;
      if (domain.isNotEmpty) return _GfwRule(domain: domain, matchType: _MatchType.domain);
    } else if (line.startsWith('|http://') || line.startsWith('|https://')) {
      final url = line.substring(1);
      final uri = Uri.tryParse(url);
      if (uri != null) return _GfwRule(domain: uri.host, matchType: _MatchType.domain);
    } else if (line.startsWith('/')) {
      return null;
    } else if (line.contains('/')) {
      return null;
    } else if (line.contains('.')) {
      return _GfwRule(domain: line, matchType: _MatchType.exact);
    }
    return null;
  }

  String _generatePacContent(List<_GfwRule> rules, int mixedPort) {
    final whitelistRules = rules.where((r) => r.isWhitelist).toList();
    final blockRules = rules.where((r) => !r.isWhitelist).toList();

    final whitelistChecks = whitelistRules.map((rule) {
      if (rule.matchType == _MatchType.domain) {
        return "  if (host.indexOf('.${rule.domain}') !== -1 || host === '${rule.domain}') return 'DIRECT';";
      } else {
        return "  if (host === '${rule.domain}') return 'DIRECT';";
      }
    }).join('\n');

    final blockChecks = blockRules.map((rule) {
      if (rule.matchType == _MatchType.domain) {
        return "  if (host.indexOf('.${rule.domain}') !== -1 || host === '${rule.domain}') return proxy;";
      } else {
        return "  if (host === '${rule.domain}') return proxy;";
      }
    }).join('\n');

    return '''
function FindProxyForURL(url, host) {
  var proxy = "PROXY 127.0.0.1:$mixedPort";
  var direct = "DIRECT";

  if (isPlainHostName(host) || host === "localhost" || host === "127.0.0.1") {
    return direct;
  }

  if (host.indexOf(':') !== -1) {
    return direct;
  }

  var ipPattern = /^(\\d{1,3}\\.){3}\\d{1,3}\$/;
  if (ipPattern.test(host)) {
    var parts = host.split('.');
    if (parts[0] === '10' || (parts[0] === '192' && parts[1] === '168') ||
        (parts[0] === '172' && parts[1] >= 16 && parts[1] <= 31)) {
      return direct;
    }
  }

$whitelistChecks

$blockChecks

  return direct;
}
''';
  }

  Future<List<String>> _getActiveNetworkServices() async {
    try {
      final result = await Process.run('networksetup', ['-listallnetworkservices']);
      final lines = (result.stdout as String).split('\n').skip(1).where((l) => l.isNotEmpty && !l.startsWith('*')).toList();
      return lines;
    } catch (e) {
      loggy.error("failed to list network services", e);
      return [];
    }
  }

  Future<void> _setSystemAutoProxy(String pacUrl) async {
    if (!Platform.isMacOS) return;

    try {
      final services = await _getActiveNetworkServices();
      for (final service in services) {
        await Process.run('networksetup', ['-setautoproxystate', service, 'on']);
        await Process.run('networksetup', ['-setautoproxyurl', service, pacUrl]);
      }
      loggy.info("system AutoProxy configured on ${services.length} services: $pacUrl");
    } catch (e) {
      loggy.error("failed to configure system AutoProxy", e);
    }
  }

  Future<void> _clearSystemAutoProxy() async {
    if (!Platform.isMacOS) return;

    try {
      final services = await _getActiveNetworkServices();
      for (final service in services) {
        await Process.run('networksetup', ['-setautoproxystate', service, 'off']);
      }
      loggy.info("system AutoProxy cleared on ${services.length} services");
    } catch (e) {
      loggy.error("failed to clear system AutoProxy", e);
    }
  }
}

enum _MatchType { domain, exact }

class _GfwRule {
  final String domain;
  final _MatchType matchType;
  final bool isWhitelist;

  _GfwRule({required this.domain, required this.matchType, this.isWhitelist = false});

  _GfwRule copyWith({bool? isWhitelist}) {
    return _GfwRule(
      domain: domain,
      matchType: matchType,
      isWhitelist: isWhitelist ?? this.isWhitelist,
    );
  }
}
