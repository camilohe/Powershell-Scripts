## Get the Mailbox to Access from the 1st commandline argument

$MailboxName = $args[0]

## Load Managed API dll  

###CHECK FOR EWS MANAGED API, IF PRESENT IMPORT THE HIGHEST VERSION EWS DLL, ELSE EXIT
$EWSDLL = (($(Get-ItemProperty -ErrorAction SilentlyContinue -Path Registry::$(Get-ChildItem -ErrorAction SilentlyContinue -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Exchange\Web Services'|Sort-Object Name -Descending| Select-Object -First 1 -ExpandProperty Name)).'Install Directory') + "Microsoft.Exchange.WebServices.dll")
if (Test-Path $EWSDLL)
    {
    Import-Module $EWSDLL
    }
else
    {
    "$(get-date -format yyyyMMddHHmmss):"
    "This script requires the EWS Managed API 1.2 or later."
    "Please download and install the current version of the EWS Managed API from"
    "http://go.microsoft.com/fwlink/?LinkId=255472"
    ""
    "Exiting Script."
    exit
    }
  
## Set Exchange Version  
$ExchangeVersion = [Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2010_SP2  
  
## Create Exchange Service Object  
$service = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService($ExchangeVersion)  
  
## Set Credentials to use two options are availible Option1 to use explict credentials or Option 2 use the Default (logged On) credentials  
  
#Credentials Option 1 using UPN for the windows Account  
$psCred = Get-Credential  
$creds = New-Object System.Net.NetworkCredential($psCred.UserName.ToString(),$psCred.GetNetworkCredential().password.ToString())  
$service.Credentials = $creds      
  
#Credentials Option 2  
#service.UseDefaultCredentials = $true  
  
## Choose to ignore any SSL Warning issues caused by Self Signed Certificates  
  
## Code From http://poshcode.org/624
## Create a compilation environment
$Provider=New-Object Microsoft.CSharp.CSharpCodeProvider
$Compiler=$Provider.CreateCompiler()
$Params=New-Object System.CodeDom.Compiler.CompilerParameters
$Params.GenerateExecutable=$False
$Params.GenerateInMemory=$True
$Params.IncludeDebugInformation=$False
$Params.ReferencedAssemblies.Add("System.DLL") | Out-Null

$TASource=@'
  namespace Local.ToolkitExtensions.Net.CertificatePolicy{
    public class TrustAll : System.Net.ICertificatePolicy {
      public TrustAll() { 
      }
      public bool CheckValidationResult(System.Net.ServicePoint sp,
        System.Security.Cryptography.X509Certificates.X509Certificate cert, 
        System.Net.WebRequest req, int problem) {
        return true;
      }
    }
  }
'@ 
$TAResults=$Provider.CompileAssemblyFromSource($Params,$TASource)
$TAAssembly=$TAResults.CompiledAssembly

## We now create an instance of the TrustAll and attach it to the ServicePointManager
$TrustAll=$TAAssembly.CreateInstance("Local.ToolkitExtensions.Net.CertificatePolicy.TrustAll")
[System.Net.ServicePointManager]::CertificatePolicy=$TrustAll

## end code from http://poshcode.org/624
  
## Set the URL of the CAS (Client Access Server) to use two options are availbe to use Autodiscover to find the CAS URL or Hardcode the CAS to use  
  
#CAS URL Option 1 Autodiscover  
$service.AutodiscoverUrl($MailboxName,{$true})  
"Using CAS Server : " + $Service.url   
   
#CAS URL Option 2 Hardcoded  
  
#$uri=[system.URI] "https://casservername/ews/exchange.asmx"  
#$service.Url = $uri    
  
## Optional section for Exchange Impersonation  
  
#$service.ImpersonatedUserId = new-object Microsoft.Exchange.WebServices.Data.ImpersonatedUserId([Microsoft.Exchange.WebServices.Data.ConnectingIdType]::SmtpAddress, $MailboxName) 

#Define Function to convert String to FolderPath  
function ConvertToString($ipInputString){  
    $Val1Text = ""  
    for ($clInt=0;$clInt -lt $ipInputString.length;$clInt++){  
            $Val1Text = $Val1Text + [Convert]::ToString([Convert]::ToChar([Convert]::ToInt32($ipInputString.Substring($clInt,2),16)))  
            $clInt++  
    }  
    return $Val1Text  
} 

#Define Extended properties  
$PR_FOLDER_TYPE = new-object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(13825,[Microsoft.Exchange.WebServices.Data.MapiPropertyType]::Integer);  
$PR_CONTAINER_CLASS_W = new-object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(0x3613,[Microsoft.Exchange.WebServices.Data.MapiPropertyType]::String);  
$folderidcnt = new-object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::ArchiveMsgFolderRoot,$MailboxName)  
#Define the FolderView used for Export should not be any larger then 1000 folders due to throttling  
$fvFolderView =  New-Object Microsoft.Exchange.WebServices.Data.FolderView(1000)  
#Deep Transval will ensure all folders in the search path are returned  
$fvFolderView.Traversal = [Microsoft.Exchange.WebServices.Data.FolderTraversal]::Shallow;  
$psPropertySet = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)  
$PR_Folder_Path = new-object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(26293, [Microsoft.Exchange.WebServices.Data.MapiPropertyType]::String);  
#Add Properties to the  Property Set  
$psPropertySet.Add($PR_Folder_Path);  
$psPropertySet.Add($PR_CONTAINER_CLASS_W)
$fvFolderView.PropertySet = $psPropertySet;  
#The Search filter will exclude any Search Folders  
$sfSearchFilter = new-object Microsoft.Exchange.WebServices.Data.SearchFilter+IsEqualTo($PR_FOLDER_TYPE,"1")  
$fiResult = $null  
#The Do loop will handle any paging that is required if there are more the 1000 folders in a mailbox  
do {  
    $fiResult = $Service.FindFolders($folderidcnt,$sfSearchFilter,$fvFolderView)  
    foreach($ffFolder in $fiResult.Folders){  
        $foldpathval = $null  
        #Try to get the FolderPath Value and then covert it to a usable String   
        if ($ffFolder.TryGetProperty($PR_Folder_Path,[ref] $foldpathval))  
        {  
            $binarry = [Text.Encoding]::UTF8.GetBytes($foldpathval)  
            $hexArr = $binarry | ForEach-Object { $_.ToString("X2") }  
            $hexString = $hexArr -join ''  
            $hexString = $hexString.Replace("FEFF", "5C00")  
            $fpath = ConvertToString($hexString)  
        }
		"Checking FolderPath : " + $fpath + " : FolderClass " + $ffFolder.FolderClass	
		$FoldeClass = $null;
		if($ffFolder.TryGetProperty($PR_CONTAINER_CLASS_W,[ref]$FoldeClass)){
			if($FoldeClass -eq "" -bor $FoldeClass -eq $null){				
				$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes",""
				$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No",""
				$choices = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)
				$message = "FolderClass Blank or null do you want to set this to IPF.Note"
				$result = $Host.UI.PromptForChoice($caption,$message,$choices,0)
				if($result -eq 0) {						
					$ffFolder.SetExtendedProperty($PR_CONTAINER_CLASS_W,"IPF.Note");
					$ffFolder.Update()
				}
				else{
					"Skipping"
				}
			}
			else{
				"Prop Found Value " + $FoldeClass
			}
			
		}
		else{
			"Prop Not Set"
		}
		#Process folder here
    } 
    $fvFolderView.Offset += $fiResult.Folders.Count
}while($fiResult.MoreAvailable -eq $true)  


