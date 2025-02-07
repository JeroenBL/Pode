Describe 'REST API Requests' {
    $splatter = @{}

    if ($PSVersionTable.PSVersion.Major -le 5) {
        Add-Type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    }
    else {
        $splatter.SkipCertificateCheck = $true
    }

    BeforeAll {
        $Port = 50010
        $Endpoint = "https://localhost:$($Port)"

        Start-Job -Name 'Pode' -ErrorAction Stop -ScriptBlock {
            Import-Module -Name "$($using:PSScriptRoot)\..\..\src\Pode.psm1"

            function Write-OuterImportedResponse {
                Write-PodeJsonResponse -Value @{ Message = 'Outer Hello' }
            }

            Start-PodeServer -RootPath $using:PSScriptRoot {
                Add-PodeEndpoint -Address localhost -Port $using:Port -Protocol Https -SelfSigned

                New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging
                Add-PodeRoute -Method Get -Path '/close' -ScriptBlock {
                    Close-PodeServer
                }

                function Write-InnerImportedResponse {
                    Write-PodeJsonResponse -Value @{ Message = 'Inner Hello' }
                }

                Add-PodeRoute -Method Get -Path '/ping' -ScriptBlock {
                    Write-PodeJsonResponse -Value @{ Result = 'Pong' }
                }

                Add-PodeRoute -Method Get -Path '/data/query' -ScriptBlock {
                    Write-PodeJsonResponse -Value @{ Username = $WebEvent.Query.username }
                }

                Add-PodeRoute -Method Post -Path '/data/payload' -ScriptBlock {
                    Write-PodeJsonResponse -Value @{ Username = $WebEvent.Data.username }
                }

                Add-PodeRoute -Method Post -Path '/data/payload-forced-type' -ContentType 'application/json' -ScriptBlock {
                    Write-PodeJsonResponse -Value @{ Username = $WebEvent.Data.username }
                }

                Add-PodeRoute -Method Get -Path '/data/param/:username' -ScriptBlock {
                    Write-PodeJsonResponse -Value @{ Username = $WebEvent.Parameters.username }
                }

                Add-PodeRoute -Method Get -Path '/data/param/:username/messages' -ScriptBlock {
                    Write-PodeJsonResponse -Value @{
                        Messages = @('Hello, world!', 'Greetings', 'Wubba Lub')
                    }
                }

                Add-PodeRoute -Method Delete -Path '/api/:username/remove' -ScriptBlock {
                    Write-PodeJsonResponse -Value @{ Result = 'OK' }
                }

                Add-PodeRoute -Method Patch -Path '/api/:username/update' -ScriptBlock {
                    Write-PodeJsonResponse -Value @{ Result = 'OK' }
                }

                Add-PodeRoute -Method Put -Path '/api/:username/replace' -ScriptBlock {
                    Write-PodeJsonResponse -Value @{ Result = 'OK' }
                }

                Add-PodeRoute -Method Post -Path '/encoding/transfer' -ScriptBlock {
                    Write-PodeJsonResponse -Value @{ Username = $WebEvent.Data.username }
                }

                Add-PodeRoute -Method Post -Path '/encoding/transfer-forced-type' -TransferEncoding 'gzip' -ScriptBlock {
                    Write-PodeJsonResponse -Value @{ Username = $WebEvent.Data.username }
                }

                Add-PodeRoute -Method * -Path '/all' -ScriptBlock {
                    Write-PodeJsonResponse -Value @{ Result ='OK' }
                }

                Add-PodeRoute -Method Get -Path '/api/*/hello' -ScriptBlock {
                    Write-PodeJsonResponse -Value @{ Result ='OK' }
                }

                Add-PodeRoute -Method Get -Path '/imported/func/outer' -ScriptBlock {
                    Write-OuterImportedResponse
                }

                Add-PodeRoute -Method Get -Path '/imported/func/inner' -ScriptBlock {
                    Write-InnerImportedResponse
                }
            }
        }

        Start-Sleep -Seconds 10
    }

    AfterAll {
        $splatter = @{}
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $splatter.SkipCertificateCheck = $true
        }

        Receive-Job -Name 'Pode' | Out-Default
        (Invoke-RestMethod -Uri "$($Endpoint)/close" -Method Get @splatter) | Out-Null
        Get-Job -Name 'Pode' | Remove-Job -Force
    }


    It 'responds back with pong' {
        $result = Invoke-RestMethod -Uri "$($Endpoint)/ping" -Method Get @splatter
        $result.Result | Should Be 'Pong'
    }

    It 'responds back with 404 for invalid route' {
        { Invoke-RestMethod -Uri "$($Endpoint)/eek" -Method Get -ErrorAction Stop @splatter } | Should Throw '404'
    }

    It 'responds back with 405 for incorrect method' {
        { Invoke-RestMethod -Uri "$($Endpoint)/ping" -Method Post -ErrorAction Stop @splatter } | Should Throw '405'
    }

    It 'responds with simple query parameter' {
        $result = Invoke-RestMethod -Uri "$($Endpoint)/data/query?username=rick" -Method Get @splatter
        $result.Username | Should Be 'rick'
    }

    It 'responds with simple payload parameter - json' {
        $result = Invoke-RestMethod -Uri "$($Endpoint)/data/payload" -Method Post -Body '{"username":"rick"}' -ContentType 'application/json' @splatter
        $result.Username | Should Be 'rick'
    }

    It 'responds with simple payload parameter - xml' {
        $result = Invoke-RestMethod -Uri "$($Endpoint)/data/payload" -Method Post -Body '<username>rick</username>' -ContentType 'text/xml' @splatter
        $result.Username | Should Be 'rick'
    }

    It 'responds with simple payload parameter forced to json' {
        $result = Invoke-RestMethod -Uri "$($Endpoint)/data/payload-forced-type" -Method Post -Body '{"username":"rick"}' @splatter
        $result.Username | Should Be 'rick'
    }

    It 'responds with simple route parameter' {
        $result = Invoke-RestMethod -Uri "$($Endpoint)/data/param/rick" -Method Get @splatter
        $result.Username | Should Be 'rick'
    }

    It 'responds with simple route parameter long' {
        $result = Invoke-RestMethod -Uri "$($Endpoint)/data/param/rick/messages" -Method Get @splatter
        $result.Messages[0] | Should Be 'Hello, world!'
        $result.Messages[1] | Should Be 'Greetings'
        $result.Messages[2] | Should Be 'Wubba Lub'
    }

    It 'responds ok to remove account' {
        $result = Invoke-RestMethod -Uri "$($Endpoint)/api/rick/remove" -Method Delete @splatter
        $result.Result | Should Be 'OK'
    }

    It 'responds ok to replace account' {
        $result = Invoke-RestMethod -Uri "$($Endpoint)/api/rick/replace" -Method Put @splatter
        $result.Result | Should Be 'OK'
    }

    It 'responds ok to update account' {
        $result = Invoke-RestMethod -Uri "$($Endpoint)/api/rick/update" -Method Patch @splatter
        $result.Result | Should Be 'OK'
    }

    It 'decodes encoded payload parameter - gzip' {
        $data = @{ username = "rick" }
        $message = ($data | ConvertTo-Json)

        # compress the message using gzip
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($message)
        $ms = New-Object -TypeName System.IO.MemoryStream
        $gzip = New-Object System.IO.Compression.GZipStream($ms, [IO.Compression.CompressionMode]::Compress, $true)
        $gzip.Write($bytes, 0, $bytes.Length)
        $gzip.Close()
        $ms.Position = 0

        # make the request
        $result = Invoke-RestMethod -Uri "$($Endpoint)/encoding/transfer" -Method Post -Body $ms.ToArray() -Headers @{ 'Transfer-Encoding' = 'gzip' } -ContentType 'application/json' @splatter
        $result.Username | Should Be 'rick'
    }

    It 'decodes encoded payload parameter - deflate' {
        $data = @{ username = "rick" }
        $message = ($data | ConvertTo-Json)

        # compress the message using deflate
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($message)
        $ms = New-Object -TypeName System.IO.MemoryStream
        $gzip = New-Object System.IO.Compression.DeflateStream($ms, [IO.Compression.CompressionMode]::Compress, $true)
        $gzip.Write($bytes, 0, $bytes.Length)
        $gzip.Close()
        $ms.Position = 0

        # make the request
        $result = Invoke-RestMethod -Uri "$($Endpoint)/encoding/transfer" -Method Post -Body $ms.ToArray() -Headers @{ 'Transfer-Encoding' = 'deflate' } -ContentType 'application/json' @splatter
        $result.Username | Should Be 'rick'
    }

    It 'decodes encoded payload parameter forced to gzip' {
        $data = @{ username = "rick" }
        $message = ($data | ConvertTo-Json)

        # compress the message using gzip
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($message)
        $ms = New-Object -TypeName System.IO.MemoryStream
        $gzip = New-Object System.IO.Compression.GZipStream($ms, [IO.Compression.CompressionMode]::Compress, $true)
        $gzip.Write($bytes, 0, $bytes.Length)
        $gzip.Close()
        $ms.Position = 0

        # make the request
        $result = Invoke-RestMethod -Uri "$($Endpoint)/encoding/transfer-forced-type" -Method Post -Body $ms.ToArray() -ContentType 'application/json' @splatter
        $result.Username | Should Be 'rick'
    }

    It 'works with any method' {
        $result = Invoke-RestMethod -Uri "$($Endpoint)/all" -Method Get @splatter
        $result.Result | Should Be 'OK'

        $result = Invoke-RestMethod -Uri "$($Endpoint)/all" -Method Put @splatter
        $result.Result | Should Be 'OK'

        $result = Invoke-RestMethod -Uri "$($Endpoint)/all" -Method Patch @splatter
        $result.Result | Should Be 'OK'
    }

    It 'route with a wild card' {
        $result = Invoke-RestMethod -Uri "$($Endpoint)/api/stuff/hello" -Method Get @splatter
        $result.Result | Should Be 'OK'

        $result = Invoke-RestMethod -Uri "$($Endpoint)/api/random/hello" -Method Get @splatter
        $result.Result | Should Be 'OK'

        $result = Invoke-RestMethod -Uri "$($Endpoint)/api/123/hello" -Method Get @splatter
        $result.Result | Should Be 'OK'
    }

    It 'route importing outer function' {
        $result = Invoke-RestMethod -Uri "$($Endpoint)/imported/func/outer" -Method Get @splatter
        $result.Message | Should Be 'Outer Hello'
    }

    It 'route importing outer function' {
        $result = Invoke-RestMethod -Uri "$($Endpoint)/imported/func/inner" -Method Get @splatter
        $result.Message | Should Be 'Inner Hello'
    }
}