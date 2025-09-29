# Test script to verify PowerShell syntax
Write-Host "Testing PowerShell syntax..." -ForegroundColor Green

# Test the Add-Type syntax
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class TestClass
{
    [DllImport("secur32.dll", CharSet = CharSet.Auto)]
    public static extern int TestFunction();
}
"@
    Write-Host "✅ Add-Type syntax is correct" -ForegroundColor Green
} catch {
    Write-Host "❌ Add-Type syntax error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "Syntax test completed." -ForegroundColor Green
