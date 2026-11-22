# アカウント単位の防止設定（C04、C05、C12）。変更は SCP で拒否している。

module "baseline_security" {
  source = "./account_baseline"
  providers = {
    aws = aws.security
  }
}

module "baseline_workload" {
  source = "./account_baseline"
  providers = {
    aws = aws.workload
  }
}
