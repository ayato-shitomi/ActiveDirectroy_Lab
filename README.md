# AWS Active Directory 演習環境

このプロジェクトは、トレーニングおよびテスト目的でAWS上にActive Directory演習環境をデプロイするためのInfrastructure as Code (IaC)を提供します。

## アーキテクチャ

```
                    ┌─────────────────────────────────────────────────────────────┐
                    │                        AWS VPC                              │
                    │                    10.100.0.0/16                            │
                    │                                                             │
┌─────────┐         │  ┌─────────────────────┐    ┌─────────────────────────────┐ │
│         │   SSH   │  │   Public Subnet     │    │      Private Subnet         │ │
│   User  │─────────|─>│   10.100.0.0/24     │    │      10.100.1.0/24          │ │
│         │         │  │                     │    │         (Pod 1)             │ │
└─────────┘         │  │  ┌─────────────┐    │    │  ┌─────┐ ┌───────┐ ┌──────┐ │ │
                    │  │  │   Bastion   │    │    │  │ DC  │ │FILESRV│ │CLIENT│ │ │
                    │  │  │   (Ubuntu)  │────┼────┼─>│ .10 │ │  .20  │ │ .30  │ │ │
                    │  │  └─────────────┘    │    │  └─────┘ └───────┘ └──────┘ │ │
                    │  │         │           │    └─────────────────────────────┘ │
                    │  │         │           │                                    │
                    │  │         ▼           │    ┌─────────────────────────────┐ │
                    │  │   ┌─────────┐       │    │      Private Subnet         │ │
                    │  │   │   IGW   │       │    │      10.100.2.0/24          │ │
                    │  │   └────┬────┘       │    │         (Pod 2)             │ │
                    │  └────────┼────────────┘    │  ┌─────┐ ┌───────┐ ┌──────┐ │ │
                    │           │                 │  │ DC  │ │FILESRV│ │CLIENT│ │ │
                    │           ▼                 │  │ .10 │ │  .20  │ │ .30  │ │ │
                    │      ┌─────────┐            │  └─────┘ └───────┘ └──────┘ │ │
                    │      │Internet │            └─────────────────────────────┘ │
                    │      └─────────┘                                            │
                    └─────────────────────────────────────────────────────────────┘
```

## コンポーネント

### Pod毎の構成
| 役割 | OS | IPアドレス | 説明 |
|------|-----|------------|-------------|
| DC | Windows Server 2022 | 10.100.X.10 | ドメインコントローラー (lab.local) |
| FILESRV | Windows Server 2022 | 10.100.X.20 | 共有フォルダを持つファイルサーバー（ドメイン参加） |
| CLIENT | Windows Server 2022 | 10.100.X.30 | スタンドアロンマシン（DNSのみDCを参照） |

### 共有リソース
| 役割 | OS | 説明 |
|------|-----|-------------|
| Bastion | Ubuntu 22.04 | プライベートサブネットへのSSHジャンプホスト |

## 前提条件

1. 適切な権限を持つ**AWSアカウント**
2. 認証情報が設定された**AWS CLI**
3. **Terraform** >= 1.0.0

## クイックスタート

### 1. クローンと設定

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars`を編集して設定を行います：

```hcl
pod_count        = 1
bastion_password = "YourSecureP@ssw0rd!"
admin_password   = "YourSecureP@ssw0rd!"
domain_password  = "YourSecureP@ssw0rd!"
allowed_ssh_cidr = "YOUR.IP.ADDRESS/32"

# 各マシンのローカル管理者パスワード（オプション、デフォルトはadmin_password）
# dc_admin_password      = "YourSecureP@ssw0rd!"
# filesrv_admin_password = "YourSecureP@ssw0rd!"
# client_admin_password  = "YourSecureP@ssw0rd!"

# ADユーザーの個別パスワード（オプション、デフォルト: P@ssw0rd!）
# user_password_hasegawa = "P@ssw0rd!"
# user_password_saitou   = "P@ssw0rd!"

# CLIENTローカルユーザーのパスワード（オプション、デフォルト: P@ssw0rd!）
# client_local_user_nagata_password = "P@ssw0rd!"
```

### 2. デプロイ

```bash
terraform init
terraform plan
terraform apply
```

### 3. 初期化の待機

Windowsサーバーは自動的に以下を実行します：
1. ネットワーク設定
2. RDP・WinRMの有効化
3. AD DSのインストール（ドメインコントローラー）
4. ドメインコントローラーへの昇格
5. OU、ユーザー、グループの作成
6. ドメイン参加（FILESRVのみ、CLIENTはスタンドアロン）
7. ファイル共有の作成（FILESRV）

このプロセスには約15〜20分かかります。

## 演習環境への接続

### BastionへのSSH接続

```bash
ssh ubuntu@<bastion-public-ip>
# パスワード: terraform.tfvarsで設定したbastion_password
```

### SSHトンネル経由でのRDP接続

ローカルマシンから：

```bash
# DCへ接続
ssh -L 3389:10.100.1.10:3389 ubuntu@<bastion-public-ip>

# FILESRVへ接続（異なるローカルポートを使用）
ssh -L 3390:10.100.1.20:3389 ubuntu@<bastion-public-ip>

# CLIENTへ接続
ssh -L 3391:10.100.1.30:3389 ubuntu@<bastion-public-ip>
```

その後、RDPで`localhost:3389`（または3390、3391）に接続します。

### WinRM経由でのPowerShellリモート接続

SSHトンネルでWinRMポートを転送：

```bash
# DCへ接続
ssh -L 5985:10.100.1.10:5985 ubuntu@<bastion-public-ip>
```

ローカルPowerShellから接続：

```powershell
$cred = Get-Credential  # Administrator / admin_password
Enter-PSSession -ComputerName localhost -Credential $cred
```

## デフォルトの認証情報

### Bastion (SSH)
- **ユーザー名:** ubuntu
- **パスワード:** （terraform.tfvarsの`bastion_password`で設定）

### ローカル管理者
- **ユーザー名:** Administrator
- **パスワード:** 各マシン毎に設定可能
  - DC: `dc_admin_password`（未設定時は`admin_password`）
  - FILESRV: `filesrv_admin_password`（未設定時は`admin_password`）
  - CLIENT: `client_admin_password`（未設定時は`admin_password`）

### CLIENTローカルユーザー
| ユーザー名 | パスワード | 説明 |
|----------|----------|-------------|
| nagata | terraform.tfvarsで設定（デフォルト: P@ssw0rd!） | CLIENT上の標準ユーザー |

パスワードは `client_local_user_nagata_password` で設定できます。
- Backup Operatorsグループ所属（SeBackupPrivilege / SeRestorePrivilege付与）
- Remote Management Usersグループ所属（WinRM接続可能）
- 標準ユーザーのため、UACによる管理者権限への昇格はできません

### ドメインユーザー
| ユーザー名 | パスワード | RDPアクセス可能なマシン | 特殊権限 |
|----------|----------|-------------|----------|
| LAB\hasegawa | terraform.tfvarsで設定（デフォルト: P@ssw0rd!） | FILESRV | FILESRVのシャットダウン権限 |
| LAB\saitou | terraform.tfvarsで設定（デフォルト: P@ssw0rd!） | FILESRV | hasegawaのパスワード変更権限 |

※ CLIENTはドメイン非参加のため、ローカルユーザー（Administrator, nagata）のみRDP可能

各ユーザーのパスワードは `user_password_hasegawa`, `user_password_saitou` で個別に設定できます。

### サービスアカウント
| ユーザー名 | 説明 | 権限 |
|----------|----------|-------------|
| LAB\svc_backup | FILESRVバックアップサービスアカウント | DCアクセス権限、Log on as a service |

### ドメイン管理者
- **ユーザー名:** LAB\Administrator
- **パスワード:** （terraform.tfvarsのdomain_passwordで設定）

## ファイル共有

| 共有名 | パス | アクセス権限 |
|-------|------|--------|
| \\\\FILESRV1\\Share | C:\Shares\Share | 全ドメインユーザーが読み書き可能 |
| \\\\FILESRV1\\Public | C:\Shares\Public | ドメインユーザーは読み取り専用 |
| \\\\FILESRV1\\Hasegawa | C:\Shares\Users\Hasegawa | hasegawaの個人フォルダ |
| \\\\FILESRV1\\Saitou | C:\Shares\Users\Saitou | saitouの個人フォルダ |

## スケジュールタスク

### FILESRV1: CheckEventNumber
- **実行タイミング:** システム起動時（120秒後）
- **実行権限:** SYSTEM（管理者権限）
- **スクリプト:** `\\FILESRV1\Hasegawa\check_event_number.bat`
- **出力:** `\\FILESRV1\Hasegawa\event_number.log`
- **内容:** System/Security/Applicationイベントログの件数を記録

## Active Directory構成

```
lab.local (ドメイン)
├── OU=LabUsers
│   ├── hasegawa
│   └── saitou
├── OU=LabComputers
├── OU=LabServers
├── OU=LabGroups
│   └── GG_Lab_Users (全演習ユーザーを含む)
└── OU=ServiceAccounts
    └── svc_backup (FILESRVバックアップサービス)
```

## トラブルシューティング

### セットアップ進行状況の確認

RDPで接続してログを確認します：

```powershell
# セットアップログを表示
Get-Content C:\ADLabLogs\userdata.log

# 現在の状態を確認
Get-Content C:\ADLabLogs\dc-state.txt  # DC用
Get-Content C:\ADLabLogs\state.txt     # FILESRV/CLIENT用
```

### スクリプトの手動実行

自動セットアップが失敗した場合、スクリプトを手動で実行できます：

```powershell
# DC上で
C:\ADLabScripts\01-install-adds.ps1
C:\ADLabScripts\02-promote-dc.ps1 -DomainName "lab.local" -DomainNetbiosName "LAB" -SafeModePassword "P@ssw0rd123!"
C:\ADLabScripts\03-configure-ad.ps1 -DomainName "lab.local"

# FILESRV/CLIENT上で
C:\ADLabScripts\01-domain-join.ps1 -DomainName "lab.local" -DomainUser "Administrator" -DomainPassword "P@ssw0rd123!" -DNSIP "10.100.1.10"
```

### よくある問題

1. **ドメイン参加に失敗**: DCが完全に構成されていることを確認。DNS設定を確認。
2. **RDP接続に失敗**: セキュリティグループがbastionからのトラフィックを許可していることを確認。
3. **ファイル共有にアクセスできない**: FILESRVがドメインに参加していることを確認。

## クリーンアップ

全リソースを削除するには：

```bash
terraform destroy
```

## コスト概算

1 Pod（Windowsインスタンス3台 + Linuxのbastion 1台）を実行した場合：
- EC2: 約$0.25/時間
- NAT Gateway: 約$0.045/時間 + データ転送
- EBS: 約$0.10/GB-月

**概算合計: Pod毎に約$8〜10/日**

## セキュリティに関する注意

- これは**トレーニング環境**であり、本番環境での使用は想定していません
- 長期間使用する場合はデフォルトパスワードを変更してください
- `allowed_ssh_cidr`を特定のIPに制限することを検討してください
- bastion以外の全インスタンスはプライベートサブネットに配置されています
- Windows UpdateのアクセスはNAT Gateway経由で提供されます

## ディレクトリ構成

```
ActiveDirectroy_Lab/
├── terraform/
│   ├── main.tf                   # プロバイダーとモジュール呼び出し
│   ├── variables.tf              # 変数定義
│   ├── outputs.tf                # 出力定義
│   ├── vpc.tf                    # VPC、サブネット、ルーティング
│   ├── security_groups.tf        # セキュリティグループ
│   ├── bastion.tf                # Bastion EC2インスタンス
│   ├── data.tf                   # AMIデータソース
│   ├── terraform.tfvars.example  # 設定例
│   └── modules/
│       └── pod/
│           ├── main.tf           # Pod EC2インスタンス
│           ├── variables.tf
│           └── outputs.tf
├── scripts/
│   ├── dc/
│   │   ├── 01-install-adds.ps1   # AD DSロールのインストール
│   │   ├── 02-promote-dc.ps1     # DCへの昇格
│   │   ├── 03-configure-ad.ps1   # ADオブジェクトの構成
│   │   └── userdata.ps1          # ブートストラップスクリプト
│   ├── filesrv/
│   │   ├── 01-domain-join.ps1    # ドメイン参加
│   │   ├── 02-create-shares.ps1  # ファイル共有の作成
│   │   └── userdata.ps1          # ブートストラップスクリプト
│   ├── client/
│   │   ├── 01-domain-join.ps1    # ドメイン参加
│   │   └── userdata.ps1          # ブートストラップスクリプト
│   └── bastion/
│       └── userdata.yaml         # Bastion cloud-init設定
└── README.md
```

## ライセンス

このプロジェクトは教育目的で提供されています。
