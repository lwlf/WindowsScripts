function Expand-IndirectString {

    Param([String] $IndirectString = "")
    
    $CSharpSHLoadIndirectString = @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace SHLWAPIDLL
{
    public class IndirectStrings
    {
        [DllImport("shlwapi.dll", CharSet=CharSet.Unicode)]
        private static extern int SHLoadIndirectString(string pszSource, StringBuilder pszOutBuf, int cchOutBuf, string ppvReserved);

        public static string GetIndirectString(string indirectString)
        {
            try
            {
                int returnValue;
                StringBuilder lptStr = new StringBuilder(1024);
                returnValue = SHLoadIndirectString(indirectString, lptStr, 1024, null);

                if (returnValue == 0)
                {
                    return lptStr.ToString();
                }
                else
                {
                    return null;
                    //return "SHLoadIndirectString Failure: " + returnValue;
                }
            }
            catch //(Exception ex)
            {
                return null;
                //return "Exception Message: " + ex.Message;
            }
        }
    }
}
'@
    
    if ("SHLWAPIDLL.IndirectStrings" -as [type]) {}
    else { Add-Type -TypeDefinition $CSharpSHLoadIndirectString -Language CSharp }
    
    [SHLWAPIDLL.IndirectStrings]::GetIndirectString($IndirectString)
    
}

function Get-AppxDisplayName {
    param (
        [Parameter(ValueFromPipeline=$true)]
        $Package
    )

    if ( $null -eq $Package ) {
        return ""
    }
    
    $manifest = $Package | Get-AppxPackageManifest
    
    if ($manifest.Package.Properties.AllowExternalContent -ne 'true') {
        $apps = $manifest.package.Applications.Application

        if ($apps.Count -gt 1) {
            $DisplayName = $manifest.Package.Properties.DisplayName
        }
        else {
            $DisplayName = $manifest.Package.Applications.Application.VisualElements.DisplayName
        }

        if ($DisplayName -match "ms-resource:") {
            if (($DisplayName -notmatch "Resources/") -and ($DisplayName -notmatch "ms-resource://")) {
                $DisplayName = $DisplayName.Insert(12, "Resources/")
            }
            $DisplayName = Expand-IndirectString "@{$($Package.PackageFullName)?$DisplayName}"
        }
    }

    return $DisplayName
}

$inputXML = @"
<Window x:Class="AppxPackageRemover.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:local="clr-namespace:AppxPackageRemover"
        mc:Ignorable="d"
        Title="AppxPackageRemover" Height="350" Width="525" x:Name="MainWindow">
	<Grid>
		<ListBox x:Name="lstPackages" Margin="10,10,10,34.96" DisplayMemberPath="Label" SelectedValuePath="Name" SelectionMode="Extended"/>
		<Button x:Name="btnRemove" Content="Remove" HorizontalAlignment="Right" Margin="0,0,10,10" Width="75" Height="19.96" VerticalAlignment="Bottom"/>
	</Grid>
</Window>
"@

$inputXML = $inputXML -replace 'mc:Ignorable="d"','' -replace "x:N",'N'  -replace '^<Win.*', '<Window'

[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
[xml]$XAML = $inputXML
#Read XAML
$reader=(New-Object System.Xml.XmlNodeReader $xaml)

try{
    $Form=[Windows.Markup.XamlReader]::Load($reader)
} catch {
    Write-Host "Unable to load Windows.Markup.XamlReader. Double-check syntax and ensure .net is installed."
}

$xaml.SelectNodes("//*[@Name]") | %{Set-Variable -Name "$($_.Name)" -Value $Form.FindName($_.Name)}

$packagesName = Get-AppxProvisionedPackage -online | Select-Object DisplayName -ExpandProperty DisplayName | Sort-Object -Unique

Write-Host "Loading..."

$packagesName | Foreach-Object {
    $packages = Get-AppxPackage -Name $_

    $packages | Foreach-Object {
        $pkg = $_
        $Name = Get-AppxDisplayName $pkg
        if ( $null -eq $Name ) {
            $Name = $pkg.Name
        }
        $PackageFullName = $pkg.PackageFullName
        
        # $lstPackages.Items.Add([pscustomobject]@{'Label'=$Name;'Name'=$PackageFullName;'IsProvisioned'=$true})
        $lstPackages.Items.Add([pscustomobject]@{'Label'=$Name;'Name'=$pkg.Name;'PackageName'=$PackageFullName})
    } | Out-Null
} | Out-Null

$btnRemove.Add_Click({$Form.DialogResult=$true; $Form.Close()})

$DialogResult = $Form.ShowDialog()

if ($DialogResult -eq $true) {
    $remove = $lstPackages.SelectedItems
    $remove | Foreach-Object {
        $LabelName = $_.Label
        $Name = $_.Name
        $PackageName = $_.PackageName

        Write-Host "Removing $LabelName ($Name)"
        Remove-AppPackage -AllUsers -Package $PackageName
    }
}

$DesktopPath=[Environment]::GetFolderPath("Desktop")
$lstPackages.SelectedItems | Export-Csv -Path "$DesktopPath\RemovedList.csv" -NoTypeInformation -Append -Encoding "utf8"

Write-Host "Removed list exproted to CSV file: `"$DesktopPath\RemovedList.csv`""
