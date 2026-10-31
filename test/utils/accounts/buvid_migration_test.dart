import 'dart:io';

import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/accounts/account_adapter.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _LegacyAdapter extends LoginAccountAdapter {
  @override
  void write(BinaryWriter writer, LoginAccount obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.cookieJar)
      ..writeByte(1)
      ..write(obj.accessKey)
      ..writeByte(2)
      ..write(obj.refresh)
      ..writeByte(3)
      ..write(obj.type.toList());
  }
}

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('piliexo-buvid-');
    Hive.init(directory.path);
    GStorage.regAdapter();
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
    Accounts.account = await Hive.openBox<LoginAccount>('account');
    await GStorage.setting.put(SettingBoxKey.buvid, 'XY-ANONYMOUS');
    AnonymousAccount().reloadBuvid();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  LoginAccount account([String? buvid]) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '123', 'bili_jct': 'test-csrf'}),
    'test-access',
    'test-refresh',
    {AccountType.video},
    buvid,
  );

  test('旧四字段账户可由新适配器读取并继承匿名标识', () async {
    Hive.registerAdapter<LoginAccount>(_LegacyAdapter(), override: true);
    var box = await Hive.openBox<LoginAccount>('legacy');
    await box.put('123', account());
    await box.close();
    Hive.registerAdapter<LoginAccount>(LoginAccountAdapter(), override: true);
    box = await Hive.openBox<LoginAccount>('legacy');
    final restored = box.get('123')!;
    expect(restored.mid, 123);
    expect(restored.buvid, 'XY-ANONYMOUS');
    expect(restored.grpcHeaders['buvid'], 'XY-ANONYMOUS');
    expect(restored.type, {AccountType.video});
    await box.close();
  });

  test('第五字段使用通用序列化，重开后保留账号独立标识', () async {
    var box = await Hive.openBox<LoginAccount>('current');
    await box.put('123', account('XY-VIDEO'));
    await box.close();
    box = await Hive.openBox<LoginAccount>('current');
    final restored = box.get('123')!;
    expect(restored.buvid, 'XY-VIDEO');
    expect(restored.grpcHeaders['buvid'], 'XY-VIDEO');
    expect(AnonymousAccount().buvid, 'XY-ANONYMOUS');
    await box.close();
  });
}
