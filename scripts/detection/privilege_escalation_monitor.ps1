# Enhanced Privilege Escalation Detection Script for CTF Environment
# Monitors for domain users being added to local Administrator groups

Write-Host "🔍 Privilege Escalation Monitor - Enhanced Detection"
Write-Host "=" * 60

# Monitor for Event 4732 (Member added to local group)
$privilegeEvents = Get-WinEvent -LogName Security -FilterHashtable @{ID=4732} -MaxEvents 50 -EA SilentlyContinue

if ($privilegeEvents) {
    Write-Host "📊 Found $($privilegeEvents.Count) group membership events"

    foreach ($event in $privilegeEvents) {
        $eventXml = [xml]$event.ToXml()
        $eventData = @{}

        # Parse event data
        foreach ($data in $eventXml.Event.EventData.Data) {
            $eventData[$data.Name] = $data.'#text'
        }

        # Check for Administrator group changes
        if ($eventData.TargetUserName -eq "Administrators") {
            $memberSid = $eventData.MemberSid
            $subjectUser = $eventData.SubjectUserName
            $eventTime = $event.TimeCreated

            # Detect domain user additions to local admin
            if ($memberSid -match "S-1-5-21-.*-11\d{2}$") {  # Domain user SID pattern
                Write-Host ""
                Write-Host "🚨 CRITICAL ALERT: Domain User Added to Local Administrators" -ForegroundColor Red
                Write-Host "⏰ Time: $eventTime"
                Write-Host "🆔 Member SID: $memberSid"
                Write-Host "👤 Changed By: $subjectUser"
                Write-Host "📋 Event ID: 4732"

                # Enhanced analysis
                $suspiciousIndicators = @()

                # Check timing (after hours = suspicious)
                if ($eventTime.Hour -lt 6 -or $eventTime.Hour -gt 22) {
                    $suspiciousIndicators += "After-hours modification"
                }

                # Check if changed by system vs user
                if ($subjectUser -like "*$" -or $subjectUser -eq "SYSTEM") {
                    $suspiciousIndicators += "System account modification"
                } else {
                    $suspiciousIndicators += "User account modification (HIGH RISK)"
                }

                # Check for common attack SIDs (1103 = hasegawa in our lab)
                if ($memberSid -match "-1103$") {
                    $suspiciousIndicators += "Known target user (hasegawa)"
                }

                Write-Host "⚠️  Risk Indicators:"
                foreach ($indicator in $suspiciousIndicators) {
                    Write-Host "   - $indicator" -ForegroundColor Yellow
                }

                # Recommended actions
                Write-Host "🔧 Recommended Actions:" -ForegroundColor Cyan
                Write-Host "   1. Verify legitimacy of this change"
                Write-Host "   2. Check for related authentication events"
                Write-Host "   3. Review file access around this time"
                Write-Host "   4. Investigate source of privilege escalation"
                Write-Host "=" * 60
            }
        }
    }
} else {
    Write-Host "❌ No group membership events found"
}

# Also monitor for user right assignments (4704)
Write-Host ""
Write-Host "🔍 Checking User Right Assignments..."
$rightEvents = Get-WinEvent -LogName Security -FilterHashtable @{ID=4704} -MaxEvents 20 -EA SilentlyContinue

if ($rightEvents) {
    Write-Host "📊 Found $($rightEvents.Count) user right assignment events"

    foreach ($event in $rightEvents) {
        $eventXml = [xml]$event.ToXml()
        Write-Host "⏰ $($event.TimeCreated) - User right assigned"
    }
} else {
    Write-Host "ℹ️  No user right assignment events found"
}

Write-Host ""
Write-Host "✅ Privilege escalation monitoring complete"