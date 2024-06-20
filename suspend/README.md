# Suspend Devlopment
 - [Private - FW - Pubic (NATGW] Type network deployment.
 - At the moment(2023/02/08), CDO doesn't support this configuration without creating additonal Security Group.

# 開発を廃棄したファイル
- Private Subnet - FW Subnet - Public Subnet (NAT GW) タイプの Network 構成用の CloudFormation
- CDO がこの Network 構成をサポートしていなかった(というのも言い過ぎかも) ため開発を中断
- CDO がこの Network 構成をデフォルトでサポートするように RFE を作成済み。Security Group を追加する事で、動作させる事はできる。