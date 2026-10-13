# Sign a script with a new self-signed code-signing certificate (trusted as a CurrentUser root),
# for execution policies that require signed scripts. On PATH via pwsh/profile.ps1.
#   Sign.ps1 -Description <certificate name> -ScriptFile <script>
# https://qiita.com/Morichan/items/f8b4bcdcde8e188058c9
Param(
  [parameter(mandatory = $true)][String]$Description,
  [parameter(mandatory = $true)][String]$ScriptFile
)
$ScriptFilePath = Convert-Path $ScriptFile
if ($null -ne $ScriptFilePath) {
  $Cert = New-SelfSignedCertificate `
    -Subject "CN=$Description, OU=Self-signed RootCA" `
    -KeyAlgorithm RSA `
    -KeyLength 4096 `
    -Type CodeSigningCert `
    -CertStoreLocation Cert:\CurrentUser\My\ `
    -NotAfter ([datetime]"2099/01/01")
  Move-Item "Cert:\CurrentUser\My\$($Cert.Thumbprint)" Cert:\CurrentUser\Root
  $RootCert = Get-Item "Cert:\CurrentUser\Root\$($Cert.Thumbprint)"
  Set-AuthenticodeSignature $ScriptFilePath $RootCert
}
