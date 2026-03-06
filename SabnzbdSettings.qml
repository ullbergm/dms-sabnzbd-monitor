import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "sabnzbdMonitor"

    StringSetting {
        settingKey: "sabUrl"
        label: "SABnzbd URL"
        description: "Base URL of your SABnzbd instance (e.g. http://localhost:8080)"
        defaultValue: "http://localhost:8080"
        placeholder: "http://localhost:8080"
    }

    StringSetting {
        settingKey: "sabApiKey"
        label: "API Key"
        description: "Your SABnzbd API key. Find it under Config → General → API Key."
        defaultValue: ""
        placeholder: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    }

    SliderSetting {
        settingKey: "refreshIntervalSec"
        label: "Refresh Interval (seconds)"
        description: "How often to poll SABnzbd. Allowed range: 2-60 seconds."
        defaultValue: 5
        minimum: 2
        maximum: 60
        unit: "sec"
    }

    SelectionSetting {
        settingKey: "pillMode"
        label: "Pill Mode"
        description: "Display mode for the status bar pill: full, text, or icon."
        options: [
            { label: "Full", value: "full" },
            { label: "Text", value: "text" },
            { label: "Icon", value: "icon" }
        ]
        defaultValue: "full"
    }

}
