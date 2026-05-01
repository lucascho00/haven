import 'package:background_fetch/background_fetch.dart';
import 'package:flutter/widgets.dart';

import '../storage/haven_cache.dart';
import 'refresh_service.dart';

@pragma('vm:entry-point')
void backgroundFetchHeadlessTask(HeadlessEvent task) async {
  final taskId = task.taskId;
  if (task.timeout) {
    BackgroundFetch.finish(taskId);
    return;
  }

  try {
    WidgetsFlutterBinding.ensureInitialized();
    await HavenCache.init();
    await RefreshService().refreshAll();
  } catch (_) {
    // Background fetch is best effort; failures should not crash the process.
  } finally {
    BackgroundFetch.finish(taskId);
  }
}

class BackgroundRefreshService {
  static Future<void> configure() async {
    await BackgroundFetch.configure(
      BackgroundFetchConfig(
        minimumFetchInterval: 15,
        stopOnTerminate: false,
        enableHeadless: true,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresStorageNotLow: false,
        requiresDeviceIdle: false,
        requiredNetworkType: NetworkType.ANY,
      ),
      (taskId) async {
        try {
          await RefreshService().refreshAll();
        } catch (_) {
          // Ignore transient network/API errors; cached content remains usable.
        } finally {
          BackgroundFetch.finish(taskId);
        }
      },
      (taskId) async {
        BackgroundFetch.finish(taskId);
      },
    );

    BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);
  }
}
