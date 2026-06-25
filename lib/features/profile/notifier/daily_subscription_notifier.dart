import 'package:dio/dio.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'daily_subscription_notifier.g.dart';

sealed class DailySubState {}

class DailySubIdle extends DailySubState {}

class DailySubLoading extends DailySubState {}

class DailySubDone extends DailySubState {
  DailySubDone({required this.added, required this.skipped, required this.failed});
  final int added;
  final int skipped;
  final int failed;
}

List<String> _buildDailyUrls() {
  final now = DateTime.now();
  final y = now.year.toString();
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  final date = '$y$m$d';
  return List.generate(5, (i) => 'https://node.freeclashnode.com/uploads/$y/$m/$i-$date.txt');
}

@riverpod
class DailySubscriptionNotifier extends _$DailySubscriptionNotifier with AppLogger {
  @override
  DailySubState build() => DailySubIdle();

  ProfileRepository get _repo => ref.read(profileRepositoryProvider).requireValue;

  Future<void> addTodaySubscriptions() async {
    if (state is DailySubLoading) return;
    state = DailySubLoading();

    final urls = _buildDailyUrls();
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
          added++;
        } else {
          failed++;
        }
      } catch (e) {
        loggy.error('daily sub: unexpected error [$url]', e);
        failed++;
      }
    }

    state = DailySubDone(added: added, skipped: skipped, failed: failed);
  }
}
