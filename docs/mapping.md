# 要件対応表

<!-- このファイルは scripts/gen_mapping.py が controls/controls.yaml から生成する。手で編集しない。 -->

- FISC 安全対策基準：未定（第13版か第14版に固定してから記入する）
- NIST：NIST SP 800-53 Rev.5（対応先は仮置き。Security Hub CSPM の対応と突き合わせて確定する）、NIST SP 800-63B-4
- 実装の欄のリンクは、その統制を実装しているファイル。リンクの実在は scripts/check_mapping.py が CI で確かめる。

| ID | 要件 | 防止 | 検知・修復 | 証跡 | NIST | FISC |
|---|---|---|---|---|---|---|
| C01 | 利用リージョンを東京と大阪に限る（大阪は Bedrock の推論だけ） | SCP [`C01DenyOutsideAllowedRegions`](../terraform/policies/scp/c01-region.json)<br>SCP [`C01DenyOsakaExceptBedrock`](../terraform/policies/scp/c01-region.json) | なし | CloudTrail の拒否記録<br>Terraform [`aws_cloudtrail.org`](../terraform/logging/main.tf) | SA-9(5) | （記入） |
| C02 | 監査ログを止めさせない、消させない | Terraform [`aws_cloudtrail.org`](../terraform/logging/main.tf)<br>SCP [`C02DenyCloudTrailChanges`](../terraform/policies/scp/c02-c03-logging.json)<br>SCP [`C02ProtectLogBucket`](../terraform/policies/scp/c02-c03-logging.json)<br>Terraform [`aws_s3_bucket_object_lock_configuration.logs`](../terraform/logging/main.tf)<br>Checkov [`CKV_AWS_36`](../.checkov.yaml)<br>Checkov [`CKV_AWS_67`](../.checkov.yaml)<br>Checkov [`CKV2_GR_C02_1`](../checkov/c02_cloudtrail.yaml) | CSPM [`CloudTrail.1`](../terraform/detection/variables.tf)<br>CSPM [`CloudTrail.4`](../terraform/detection/variables.tf) | ログファイルの検証（ダイジェスト） | AU-9<br>AU-12 | （記入） |
| C03 | 構成の記録を止めさせない | SCP [`C03DenyConfigChanges`](../terraform/policies/scp/c02-c03-logging.json) | CSPM [`Config.1`](../terraform/detection/variables.tf) | Config の記録履歴<br>Terraform [`aws_config_configuration_aggregator.org`](../terraform/detection/config.tf) | CM-8<br>CA-7 | （記入） |
| C04 | 保存データを暗号化する（EBS） | Terraform [`aws_ebs_encryption_by_default.this`](../terraform/policies/account_baseline/main.tf)<br>SCP [`C04DenyDisableEbsDefaultEncryption`](../terraform/policies/scp/c04-c09-baseline.json)<br>Checkov [`CKV_AWS_3`](../.checkov.yaml)<br>Checkov [`CKV_AWS_8`](../.checkov.yaml)<br>Checkov [`CKV2_GR_C04_1`](../checkov/c04_ebs.yaml) | Config [`c04-encrypted-volumes`](../terraform/detection/config.tf)<br>CSPM [`EC2.7`](../terraform/detection/variables.tf) | Config の評価履歴 | SC-28 | （記入） |
| C05 | S3 を公開させない | Terraform [`aws_s3_account_public_access_block.this`](../terraform/policies/account_baseline/main.tf)<br>SCP [`C05DenyAccountPublicAccessBlockChange`](../terraform/policies/scp/c04-c09-baseline.json)<br>Checkov [`CKV2_GR_C05_1`](../checkov/c05_s3_account_bpa.yaml) | CSPM [`S3.1`](../terraform/detection/variables.tf) | Config の評価履歴 | AC-3<br>SC-7 | （記入） |
| C06 | 通信を暗号化する（S3 は TLS 必須） | RCP [`C06DenyS3WithoutTLS`](../terraform/policies/rcp/c06-s3-tls.json)<br>Terraform [`aws_s3_bucket_policy.logs`](../terraform/logging/main.tf) | Config [`c06-s3-bucket-ssl-requests-only`](../terraform/detection/config.tf)<br>CSPM [`S3.5`](../terraform/detection/variables.tf) | CloudTrail の拒否記録（GetObject などはデータイベントなので、データイベントを有効にしたバケットだけ） | SC-8 | （記入） |
| C07 | 長期の認証情報を作らせない | SCP [`C07DenyLongTermCredentials`](../terraform/policies/scp/c04-c09-baseline.json) | なし | CloudTrail の拒否記録 | IA-5<br>AC-2 | （記入） |
| C08 | 人のログインは MFA 必須 | 手続き：IAM Identity Center で MFA を必須にする（コンソールでしか設定できない）<br>Terraform [`aws_ssoadmin_permission_set.admin`](../terraform/org/identity_center.tf) | なし | 設定画面の記録と手順書 | IA-2(1)<br>800-63B-4 AAL2 | （記入） |
| C09 | メンバーアカウントのルートを使わせない | Terraform [`aws_iam_organizations_features.root_access`](../terraform/org/main.tf)<br>SCP [`C09DenyRootUser`](../terraform/policies/scp/c04-c09-baseline.json) | CSPM [`IAM.4`](../terraform/detection/variables.tf) | CloudTrail の拒否記録 | AC-6 | （記入） |
| C10 | 管理用ポートを全世界に開けさせない | 手続き：実行時の防止はなし（開放先の CIDR を IAM の条件で判定できない）。Terraform の変更は CI で事前に止める（C11）<br>Checkov [`CKV_AWS_24`](../.checkov.yaml)<br>Checkov [`CKV_AWS_25`](../.checkov.yaml)<br>Checkov [`CKV2_GR_C10_1`](../checkov/c10_ssh_ipv6.yaml) | Config [`c10-restricted-ssh`](../terraform/detection/config.tf)<br>CSPM [`EC2.13`](../terraform/detection/variables.tf)<br>Terraform [`aws_config_remediation_configuration.c10`](../terraform/remediation/main.tf)<br>SSM [`AWS-DisablePublicAccessForSecurityGroup`](../terraform/remediation/main.tf) | 修復の実行履歴と所要時間（中央値と最大値） | SC-7<br>CM-7 | （記入） |
| C11 | 違反を含む変更を反映させない | 手続き：Checkov が失敗したプルリクエストはマージできない（ブランチ保護） | なし | プルリクエストと CI の履歴<br>各チェックが効くことを、違反ありと違反なしのサンプルで確かめる（scripts/test_checkov_fixtures.py） | CM-3 | （記入） |
| C12 | パスワードの規則（基準の衝突） | 手続き：C07 で IAM ユーザー自体を作らせない<br>Terraform [`aws_iam_account_password_policy.this`](../terraform/policies/account_baseline/main.tf) | Config [`c12-iam-password-policy`](../terraform/detection/config.tf) | 判断の記録（この notes） | IA-5(1)<br>800-63B-4 3.1.1.2 | （記入） |

## 注記

- **C01**：大阪は P3 の Bedrock（jp. で始まる推論プロファイル）の推論先としてだけ許可する。 許可外のリージョンでの拒否も記録するため、組織証跡はマルチリージョンにしている。
- **C02**：組織証跡はメンバーアカウントからは変更できない。Object Lock は学習用なのでガバナンスモードで1日にしている。
- **C03**：停止と削除のほか、記録対象を空にする PutConfigurationRecorder と、ルールや修復設定の削除も拒否する。
- **C06**：Config のルールはバケットポリシーしか見ないので、RCP で防いでいても違反と出る。 ログバケットにはバケットポリシーでも TLS 必須を書いた。ほかのバケットで違反と出たら、理由を付けて抑制する。
- **C07**：IAM ユーザーそのものを作らせないので、検知の対象がない。人は Identity Center、システムはロールを使う。
- **C08**：MFA が未登録の人にメールでワンタイムパスワードを送る設定にはしない（800-63B ではメールを帯域外の認証器に使えない）。 未登録のときは、サインイン時に登録を必須にする。
- **C11**：Checkov は統制に関係するチェックだけを有効にする（.checkov.yaml）。各チェックの ID は、対応する統制（C02、C04、C05、C10）の防止の欄に書く。 CIS 由来のパスワード規則（CKV_AWS_9〜15）は、C12 の判断により使わない。
- **C12**：Config の iam-password-policy は既定で大文字・小文字・数字・記号を求めるが、 800-63B-4 は文字種の組み合わせ規則を課してはならないとする。800-63B-4 に合わせ、文字種は求めず長さ15文字以上を見る設定にした。 ただし人が実際に使うのは Identity Center のパスワードで、文字種が必須かつ変更できないとされる（要確認）。 ここは同じ衝突が設定では解けないので、MFA 必須（C08）で補い、残るリスクとして記録する。 IAM のパスワードポリシーでは、800-63B-4 が求めるブロックリストとの照合もできない。
