# 開発規約

このプロジェクトは、トレーニングおよびテスト目的でAWS上にActive Directory演習環境をデプロイするためのInfrastructure as Code (IaC)を提供します。

## コード作成
- コード作成にプロジェクトの背景を理解するようにしてください
- コード作成後にコードが正しく動くか厳密な確認を行ってください
- コード作成後に他のコードへの影響がないか厳密な確認を行ってください

## デプロイ
- デプロイ、再デプロイをしたい時にはコマンドを教えてください。手動でデプロイします
- yesと入力せずにデプロイできるように自動アセプトの引数を付けてコマンドを教えてください

## デバッグ
- 自律的なデバッグを行ってください
- 各ホストのRDPは`3389:10.100.1.10:3389`, `3390:10.100.1.20:3389`, `3391:10.100.1.30:3389`にバインドされています
- 各ホストのSMBは`445:10.100.1.10:445`, `446:10.100.1.20:445`, `447:10.100.1.30:445`にバインドされています
- 各ホストのWinRMは`5985:10.100.1.10:5985`, `5986:10.100.1.20:5985`, `5987:10.100.1.30:5985`にバインドされています
- デプロイされた環境のデバッグには上記ローカルポートを利用してください
- 主にnetexecを利用して確認を行ってください

### 成功パターンの確認方法
セットアップ完了後の動作確認には以下のコマンドを使用：

```bash
# ドメインユーザーでのRDP接続確認（FILESRV）
netexec rdp localhost -u hasegawa saitou -p 'P@ssw0rd!' --port 3390 -d LAB --continue-on-success

# 管理者でのRDP接続確認（FILESRV）
netexec rdp localhost -u Administrator -p 'P@ssw0rd123!' --port 3390 --continue-on-success

# ドメインユーザーでのRDP接続確認（DC）
netexec rdp localhost -u hasegawa saitou -p 'P@ssw0rd!' --port 3389 -d LAB --continue-on-success
```

### タイミング考慮事項
- セットアップ完了まで15-20分程度かかる場合がある
- デバッグ時にSTATUS_LOGON_FAILUREが発生してもセットアップ進行中の可能性
- 適切な間隔を置いて再テストを実施する

## FILESRV重要機能チェックリスト

### 削除された機能の事例と再発防止

**2026年2月の機能削除事例:**
1. **check_event_number.batの機能不全**
   - 削除された機能: イベントログカウント（System/Security/Application）
   - 削除された機能: hasegawa所有権設定（icacls）
   - 影響: hasegawaがファイルを編集できない

2. **SeShutdownPrivilege削除**
   - 削除された機能: hasegawaへのシャットダウン権限付与
   - 影響: hasegawaがFILESRVをシャットダウンできない

### FILESRVスクリプト修正時の必須確認事項

**機能完全性チェックリスト:**
- [ ] **状態管理**: INIT→WAIT→JOIN→SHARE→DONE遷移
- [ ] **ドメイン参加**: 10回リトライ機能付き
- [ ] **SMB共有作成**: Share, Public, Hasegawa, Saitou
- [ ] **ADユーザー権限**: Remote Desktop Users, Remote Management Users追加
- [ ] **svc_backup設定**: 管理者権限付与、クレデンシャルキャッシュ
- [ ] **check_event_number.bat**: イベントログカウント機能（System/Security/Application）
- [ ] **hasegawa所有権**: icaclsによるModify権限付与
- [ ] **SeShutdownPrivilege**: hasegawaへのシャットダウン権限
- [ ] **RDP設定**: fDenyTSConnections無効化 + NLA無効化（UserAuthentication=0）
- [ ] **スケジュールタスク**: CheckEventNumber, LogBackup作成
- [ ] **ファイルサイズ**: AWS制限16,384文字以下

**テンプレート構文注意事項:**
- Terraformのtemplatefileは PowerShell構文と競合する
- バッククォート（`）、三重引用符（'''）、特殊文字を避ける
- 変数代入のみtemplatefile使用、複雑処理は実行時動的構築

**確認コマンド:**
```bash
# RDP権限確認（重要！）
netexec rdp localhost -u hasegawa saitou -p 'P@ssw0rd!' --port 3390 -d LAB --continue-on-success

# Remote Desktop Usersグループ確認
netexec winrm localhost --port 5986 -u hasegawa -p 'P@ssw0rd!' -d LAB -x "Get-LocalGroupMember -Group 'Remote Desktop Users'"

# hasegawaファイル編集権限確認
netexec smb localhost --port 446 -u hasegawa -p 'P@ssw0rd!' -d LAB --shares

# イベントログ出力確認
cat /mnt/c/shares/hasegawa/event_number.log

# svc_backupクレデンシャル確認
pypykatz lsa minidump lsass.DMP | grep svc_backup
```

## コミット
- 適宜コミットとPushを行ってください
- コミットメッセージにAgentのクレジットを含めないでください