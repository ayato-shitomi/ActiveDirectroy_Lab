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
| FILESRV | Windows Server 2022 | 10.100.X.20 | 共有フォルダを持つファイルサーバー |
| CLIENT | Windows Server 2022 | 10.100.X.30 | ドメイン参加済みクライアントマシン |

### 共有リソース
| 役割 | OS | 説明 |
|------|-----|-------------|
| Bastion | Ubuntu 22.04 | プライベートサブネットへのSSHジャンプホスト |

## 前提条件

1. 適切な権限を持つ**AWSアカウント**
2. 認証情報が設定された**AWS CLI**
3. **Terraform** >= 1.0.0
4. 対象リージョンで作成済みの**EC2キーペア**

## クイックスタート

### 1. クローンと設定

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars`を編集して設定を行います：

```hcl
pod_count        = 1
key_name         = "your-keypair-name"
admin_password   = "YourSecureP@ssw0rd!"
domain_password  = "YourSecureP@ssw0rd!"
allowed_ssh_cidr = "YOUR.IP.ADDRESS/32"
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
2. AD DSのインストール（ドメインコントローラー）
3. ドメインコントローラーへの昇格
4. OU、ユーザー、グループの作成
5. ドメイン参加（FILESRVとCLIENT）
6. ファイル共有の作成（FILESRV）

このプロセスには約15〜20分かかります。

## 演習環境への接続

### BastionへのSSH接続

```bash
ssh -i your-key.pem ubuntu@<bastion-public-ip>
```

### SSHトンネル経由でのRDP接続

ローカルマシンから：

```bash
# DCへ接続
ssh -L 3389:10.100.1.10:3389 -i your-key.pem ubuntu@<bastion-public-ip>

# FILESRVへ接続（異なるローカルポートを使用）
ssh -L 3390:10.100.1.20:3389 -i your-key.pem ubuntu@<bastion-public-ip>

# CLIENTへ接続
ssh -L 3391:10.100.1.30:3389 -i your-key.pem ubuntu@<bastion-public-ip>
```

その後、RDPで`localhost:3389`（または3390、3391）に接続します。

## デフォルトの認証情報

### ローカル管理者
- **ユーザー名:** Administrator
- **パスワード:** （terraform.tfvarsで設定）

### ドメインユーザー
| ユーザー名 | パスワード | 説明 |
|----------|----------|-------------|
| LAB\tanaka | P@ssw0rd! | 演習用ユーザー |
| LAB\hasegawa | P@ssw0rd! | 演習用ユーザー |
| LAB\saitou | P@ssw0rd! | 演習用ユーザー |

### ドメイン管理者
- **ユーザー名:** LAB\Administrator
- **パスワード:** （terraform.tfvarsのdomain_passwordで設定）

## ファイル共有

| 共有名 | パス | アクセス権限 |
|-------|------|--------|
| \\\\FILESRV1\\Share | C:\Shares\Share | 全ドメインユーザーが読み書き可能 |
| \\\\FILESRV1\\Public | C:\Shares\Public | ドメインユーザーは読み取り専用 |
| \\\\FILESRV1\\Tanaka | C:\Shares\Users\Tanaka | tanakaの個人フォルダ |
| \\\\FILESRV1\\Hasegawa | C:\Shares\Users\Hasegawa | hasegawaの個人フォルダ |
| \\\\FILESRV1\\Saitou | C:\Shares\Users\Saitou | saitouの個人フォルダ |

## Active Directory構成

```
lab.local (ドメイン)
├── OU=LabUsers
│   ├── tanaka
│   ├── hasegawa
│   └── saitou
├── OU=LabComputers
├── OU=LabServers
└── OU=LabGroups
    └── GG_Lab_Users (全演習ユーザーを含む)
```

## トラブルシューティング

### セットアップ進行状況の確認

RDPで接続してログを確認します：

```powershell
# セットアップログを表示
Get-Content C:\ADLabLogs\userdata.log

# 現在の状態を確認
Get-Content C:\ADLabLogs\dc-state.txt      # DC用
Get-Content C:\ADLabLogs\filesrv-state.txt # FILESRV用
Get-Content C:\ADLabLogs\client-state.txt  # CLIENT用
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
│       └── setup.sh              # Bastionセットアップスクリプト
└── README.md
```

## ライセンス

このプロジェクトは教育目的で提供されています。
