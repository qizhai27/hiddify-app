import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'daily_subscription_notifier.g.dart';

enum DailySubMode { txt, json }

sealed class DailySubState {}

class DailySubIdle extends DailySubState {}

class DailySubLoading extends DailySubState {}

class DailySubDone extends DailySubState {
  DailySubDone({required this.added, required this.skipped, required this.failed, required this.deleted});
  final int added;
  final int skipped;
  final int failed;
  final int deleted;
}

const _kServerHost = 'node.freeclashnode.com';

List<String> _buildDailyTxtUrls() {
  final now = DateTime.now();
  final y = now.year.toString();
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  final date = '$y$m$d';
  return List.generate(5, (i) => 'https://$_kServerHost/uploads/$y/$m/$i-$date.txt');
}

String _buildDailyJsonUrl() {
  final now = DateTime.now();
  final y = now.year.toString();
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  final date = '$y$m$d';
  return 'https://$_kServerHost/uploads/$y/$m/$date.json';
}

String _suffixOf(DailySubMode mode) => mode == DailySubMode.txt ? 'v2ray' : 'sing-box';

@riverpod
class DailySubscriptionNotifier extends _$DailySubscriptionNotifier with AppLogger {
  @override
  DailySubState build() => DailySubIdle();

  ProfileRepository get _repo => ref.read(profileRepositoryProvider).requireValue;

  Future<void> addTodaySubscriptions(DailySubMode mode) async {
    if (state is DailySubLoading) return;
    state = DailySubLoading();

    final urls = mode == DailySubMode.txt ? _buildDailyTxtUrls() : [_buildDailyJsonUrl()];
    final todayUrlSet = urls.toSet();
    int added = 0, skipped = 0, failed = 0;

    for (final url in urls) {
      try {
        final existing = await ref.read(profileDataSourceProvider).getByUrl(url);
        if (existing != null) {
          skipped++;
          loggy.debug('daily sub: skipped existing [$url]');
          continue;
        }

        final result = await _repo
            .upsertRemote(url, cancelToken: CancelToken())
            .match(
              (err) {
                loggy.warning('daily sub: failed [$url]', err);
                return false;
              },
              (_) {
                loggy.info('daily sub: added [$url]');
                return true;
              },
            )
            .run();

        if (result) {
          await _appendNameSuffix(url, mode);
          added++;
        } else {
          failed++;
        }
      } catch (e) {
        loggy.error('daily sub: unexpected error [$url]', e);
        failed++;
      }
    }

    final deleted = await _cleanupOutdatedSubscriptions(todayUrlSet, mode);

    state = DailySubDone(added: added, skipped: skipped, failed: failed, deleted: deleted);
  }

  Future<void> _appendNameSuffix(String url, DailySubMode mode) async {
    try {
      final prof = await ref.read(profileDataSourceProvider).getByUrl(url);
      if (prof == null || prof.name.isEmpty) return;
      final suffix = _suffixOf(mode);
      final suffixMark = ' - $suffix';
      if (prof.name.endsWith(suffixMark)) return;
      final newName = '${prof.name}$suffixMark';
      await ref.read(profileDataSourceProvider).edit(
        prof.id,
        ProfileEntriesCompanion(name: Value(newName)),
      );
    } catch (e) {
      loggy.error('daily sub: failed to append suffix [$url]', e);
    }
  }

  Future<int> _cleanupOutdatedSubscriptions(Set<String> todayUrlSet, DailySubMode mode) async {
    try {
      final allProfiles = await ref
          .read(profileDataSourceProvider)
          .watchAll(sort: ProfilesSort.lastUpdate, sortMode: SortMode.ascending)
          .first;

      final suffix = mode == DailySubMode.txt ? '.txt' : '.json';

      final toDelete = allProfiles.where((p) {
        final url = p.url;
        if (url == null || url.isEmpty) return false;
        if (!url.contains(_kServerHost)) return false;
        if (!url.endsWith(suffix)) return false;
        if (todayUrlSet.contains(url)) return false;
        return true;
      }).toList();

      if (toDelete.isEmpty) return 0;

      int deleted = 0;
      for (final p in toDelete) {
        try {
          await ref.read(profileDataSourceProvider).deleteById(p.id, p.active);
          deleted++;
          loggy.info('daily sub: deleted outdated [${p.url}]');
        } catch (e) {
          loggy.error('daily sub: failed to delete [${p.url}]', e);
        }
      }
      return deleted;
    } catch (e) {
      loggy.error('daily sub: cleanup failed', e);
      return 0;
    }
  }
}
