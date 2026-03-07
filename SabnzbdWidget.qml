import QtQuick
import Quickshell

import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // --- State ---
    property string sabStatus: "offline"   // "downloading", "paused", "idle", "offline"
    property string rawStatus: ""
    property string speed: ""
    property string sizeLeft: ""
    property string timeLeft: ""
    property int queueSlots: 0
    property string currentJobName: ""
    property string currentJobProgress: ""

    property bool apiError: false
    property string errorMessage: ""
    property bool actionBusy: false
    property string actionMessage: ""

    // --- Settings ---
    property string sabUrl: pluginData.sabUrl || "http://localhost:8080"
    property string sabApiKey: pluginData.sabApiKey || ""
    property var refreshIntervalSetting: pluginData.refreshIntervalSec
    property string pillModeSetting: pluginData.pillMode || "full"

    // --- Polling and URL state ---
    readonly property int baseInterval: parseRefreshIntervalMs(refreshIntervalSetting)
    property int currentInterval: baseInterval
    property int consecutiveFailures: 0
    property int maxBackoffInterval: 60000
    property bool requestInFlight: false
    readonly property string normalizedSabUrl: normalizeUrl(sabUrl)
    readonly property bool validSabUrl: isValidUrl(normalizedSabUrl)
    readonly property string normalizedPillMode: normalizePillMode(pillModeSetting)

    // Reset currentInterval when base changes (only if no active backoff).
    onBaseIntervalChanged: {
        if (consecutiveFailures === 0)
            currentInterval = baseInterval
    }

    // ---------------------------------------------------------------
    // Periodic refresh
    // ---------------------------------------------------------------
    Timer {
        id: pollTimer
        interval: root.currentInterval
        running: root.sabApiKey.trim() !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetchQueue()
    }

    Timer {
        id: actionMessageTimer
        interval: 4000
        repeat: false
        onTriggered: root.actionMessage = ""
    }

    // ---------------------------------------------------------------
    // API calls
    // ---------------------------------------------------------------
    function callApi(params, onSuccess, onFailure) {
        if (sabApiKey.trim() === "") {
            if (onFailure) onFailure("missing_key")
            return
        }
        if (!validSabUrl) {
            if (onFailure) onFailure("invalid_url")
            return
        }

        var xhr = new XMLHttpRequest()
        var url = normalizedSabUrl + "/api?apikey=" + encodeURIComponent(sabApiKey)

        for (var k in params)
            url += "&" + encodeURIComponent(k) + "=" + encodeURIComponent(params[k])

        xhr.timeout = 5000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            if (xhr.status === 200) {
                try {
                    var obj = JSON.parse(xhr.responseText)
                    if (onSuccess) onSuccess(obj)
                } catch (e) {
                    if (onFailure) onFailure("invalid_json")
                }
                return
            }

            if (xhr.status === 401 || xhr.status === 403) {
                if (onFailure) onFailure("auth")
            } else if (xhr.status === 404) {
                if (onFailure) onFailure("not_found")
            } else if (xhr.status === 0) {
                if (onFailure) onFailure("unreachable")
            } else {
                if (onFailure) onFailure("http_" + xhr.status)
            }
        }

        xhr.ontimeout = function() {
            if (onFailure) onFailure("timeout")
        }

        xhr.open("GET", url)
        xhr.send()
    }

    function fetchQueue() {
        if (requestInFlight)
            return

        requestInFlight = true
        callApi(
            { mode: "queue", output: "json" },
            function(obj) {
                requestInFlight = false
                if (handleQueueResponse(obj))
                    setApiSuccess()
            },
            function(reason) {
                requestInFlight = false
                setApiFailure(reason)
            }
        )
    }

    function handleQueueResponse(obj) {
        if (obj.status === false || obj.status === "false") {
            var apiErr = (obj.error || "").toLowerCase()
            if (apiErr.indexOf("api") !== -1 && apiErr.indexOf("key") !== -1) {
                setApiFailure("auth")
            } else {
                setApiFailure("api_error")
            }
            return false
        }

        var q = obj.queue
        if (!q) {
            setApiFailure("invalid_payload")
            return false
        }

        rawStatus = q.status || ""
        queueSlots = parseInt(q.noofslots) || 0
        timeLeft = q.timeleft || ""
        sizeLeft = q.sizeleft || ""

        var kbps = parseFloat(q.kbpersec) || 0
        if (kbps > 0) {
            if (kbps >= 1024) {
                speed = (kbps / 1024).toFixed(1) + " MB/s"
            } else {
                speed = kbps.toFixed(0) + " KB/s"
            }
        } else {
            speed = ""
        }

        var slots = q.slots || []
        if (slots.length > 0) {
            var first = slots[0]
            currentJobName = first.filename || first.nzo_id || ""
            var p = first.percentage || ""
            currentJobProgress = p !== "" ? (p.toString().indexOf("%") === -1 ? p + "%" : p) : ""
        } else {
            currentJobName = ""
            currentJobProgress = ""
        }

        var s = (q.status || "").toLowerCase()
        if (s === "downloading") {
            sabStatus = "downloading"
        } else if (s === "paused") {
            sabStatus = "paused"
        } else {
            sabStatus = "idle"
        }

        return true
    }

    function sendQueueAction(mode) {
        if (actionBusy)
            return

        actionBusy = true
        actionMessage = ""

        callApi(
            { mode: mode, output: "json" },
            function(_) {
                actionBusy = false
                actionMessage = mode === "pause" ? "Queue paused" : "Queue resumed"
                actionMessageTimer.restart()
                fetchQueue()
            },
            function(reason) {
                actionBusy = false
                actionMessage = "Action failed: " + errorMessageFor(reason)
                actionMessageTimer.restart()
                setApiFailure(reason)
            }
        )
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------
    function normalizeUrl(input) {
        var s = (input || "").trim()
        if (s === "") return ""
        if (!/^https?:\/\//i.test(s)) s = "http://" + s
        s = s.replace(/\/+$/, "")
        return s
    }

    function isValidUrl(input) {
        if (!input || input === "") return false
        return /^https?:\/\/[^\s]+$/i.test(input)
    }

    function parseRefreshIntervalMs(rawValue) {
        var normalized = rawValue
        if (normalized === undefined || normalized === null || normalized === "")
            normalized = 5
        var sec = parseInt(normalized, 10)
        if (isNaN(sec)) sec = 5
        if (sec < 2) sec = 2
        if (sec > 60) sec = 60
        return sec * 1000
    }

    function normalizePillMode(rawValue) {
        var mode = (rawValue || "full").toString().trim().toLowerCase()
        if (mode === "icon" || mode === "text" || mode === "full")
            return mode
        return "full"
    }

    function setApiSuccess() {
        apiError = false
        errorMessage = ""
        consecutiveFailures = 0
        currentInterval = baseInterval
    }

    function setApiFailure(reason) {
        apiError = true
        sabStatus = "offline"
        errorMessage = errorMessageFor(reason)
        consecutiveFailures += 1
        var next = baseInterval * Math.pow(2, consecutiveFailures)
        currentInterval = Math.min(maxBackoffInterval, next)
        pollTimer.restart()
    }

    function errorMessageFor(reason) {
        if (reason === "missing_key") return "API key not configured"
        if (reason === "invalid_url") return "Invalid SABnzbd URL"
        if (reason === "auth") return "Authentication failed (check API key)"
        if (reason === "not_found") return "SABnzbd API endpoint not found"
        if (reason === "timeout") return "Request timed out"
        if (reason === "unreachable") return "Unable to reach SABnzbd"
        if (reason === "invalid_json") return "Invalid response from SABnzbd"
        if (reason === "invalid_payload") return "Unexpected queue payload"
        if (reason === "api_error") return "SABnzbd returned an API error"
        return "Request failed"
    }

    function statusColor() {
        switch (sabStatus) {
            case "downloading": return Theme.primary
            case "paused": return "#ffa040"
            case "idle": return Theme.surfaceVariantText
            default: return Theme.error
        }
    }

    function statusIcon() {
        switch (sabStatus) {
            case "downloading": return "download"
            case "paused": return "pause_circle"
            case "idle": return "inbox"
            default: return "cloud_off"
        }
    }

    function statusLabel() {
        if (sabApiKey.trim() === "") return "Set API Key"
        if (!validSabUrl) return "Invalid URL"
        if (apiError) return "Offline"
        if (sabStatus === "downloading") return speed !== "" ? speed : "Downloading"
        if (sabStatus === "paused") return "Paused"
        if (sabStatus === "idle") return "Idle"
        return "Offline"
    }

    // ---------------------------------------------------------------
    // Status bar pill
    // ---------------------------------------------------------------
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            DankIcon {
                name: root.statusIcon()
                color: root.statusColor()
                anchors.verticalCenter: parent.verticalCenter
                visible: root.normalizedPillMode !== "text"
            }

            StyledText {
                text: root.statusLabel()
                font.pixelSize: Theme.fontSizeSmall
                color: root.statusColor()
                anchors.verticalCenter: parent.verticalCenter
                visible: root.normalizedPillMode !== "icon"
            }
        }
    }

    // ---------------------------------------------------------------
    // Popout panel
    // ---------------------------------------------------------------
    popoutContent: Component {
        PopoutComponent {
            headerText: "SABnzbd"
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingL

                Row {
                    width: parent.width
                    spacing: Theme.spacingM

                    DankIcon {
                        name: root.statusIcon()
                        color: root.statusColor()
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: root.apiError ? root.errorMessage :
                              (root.rawStatus !== "" ? root.rawStatus : "-")
                        font.pixelSize: Theme.fontSizeLarge
                        font.bold: true
                        color: root.statusColor()
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.sabApiKey.trim() !== "" && root.validSabUrl

                    Repeater {
                        model: [
                            { label: "Pause",   action: "pause",   usesBusy: true  },
                            { label: "Resume",  action: "resume",  usesBusy: true  },
                            { label: "Refresh", action: "refresh", usesBusy: false }
                        ]

                        delegate: Rectangle {
                            required property var modelData

                            width: btnLabel.implicitWidth + Theme.spacingM * 2
                            height: btnLabel.implicitHeight + Theme.spacingS * 2
                            radius: Theme.cornerRadius
                            color: Theme.surfaceVariant
                            opacity: modelData.usesBusy && root.actionBusy ? 0.6 : 1

                            StyledText {
                                id: btnLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !(modelData.usesBusy && root.actionBusy)
                                onClicked: {
                                    if (modelData.action === "refresh")
                                        root.fetchQueue()
                                    else
                                        root.sendQueueAction(modelData.action)
                                }
                            }
                        }
                    }
                }

                StyledText {
                    visible: root.actionMessage !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: root.actionMessage
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: !root.apiError && root.sabStatus !== "offline"

                    Row {
                        width: parent.width
                        visible: root.currentJobName !== ""
                        StyledText {
                            width: parent.width * 0.5
                            text: "Current job"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        StyledText {
                            width: parent.width * 0.5
                            text: root.currentJobName
                            elide: Text.ElideRight
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                        }
                    }

                    Row {
                        width: parent.width
                        visible: root.currentJobProgress !== ""
                        StyledText {
                            width: parent.width * 0.5
                            text: "Job progress"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        StyledText {
                            text: root.currentJobProgress
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                        }
                    }

                    Row {
                        width: parent.width
                        visible: root.speed !== ""
                        StyledText {
                            width: parent.width * 0.5
                            text: "Speed"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        StyledText {
                            text: root.speed
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                        }
                    }

                    Row {
                        width: parent.width
                        visible: root.sizeLeft !== "" && root.sizeLeft !== "0 B"
                        StyledText {
                            width: parent.width * 0.5
                            text: "Remaining"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        StyledText {
                            text: root.sizeLeft
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                        }
                    }

                    Row {
                        width: parent.width
                        visible: root.timeLeft !== "" && root.timeLeft !== "0:00:00"
                        StyledText {
                            width: parent.width * 0.5
                            text: "Time left"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        StyledText {
                            text: root.timeLeft
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                        }
                    }

                    Row {
                        width: parent.width
                        visible: root.queueSlots > 0
                        StyledText {
                            width: parent.width * 0.5
                            text: "Queue items"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        StyledText {
                            text: root.queueSlots.toString()
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                        }
                    }
                }

                StyledText {
                    visible: root.sabApiKey.trim() === ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Open plugin settings and enter your SABnzbd URL and API key."
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                StyledText {
                    visible: root.sabApiKey.trim() !== "" && !root.validSabUrl
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "The configured SABnzbd URL is invalid. Use http://host:port."
                    color: Theme.error
                    font.pixelSize: Theme.fontSizeSmall
                }

                StyledText {
                    visible: root.apiError && root.sabApiKey.trim() !== "" && root.validSabUrl
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Retrying every " + Math.round(root.currentInterval / 1000) + "s (backoff active)."
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }
}
