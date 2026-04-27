pragma Singleton
import QtQuick

QtObject {
    // ═══════════════════════════════════════════════════════════
    //  PREMIUM DESIGN TOKENS — Carbon + Gold aerospace palette
    // ═══════════════════════════════════════════════════════════

    // Backgrounds (darkest → lightest)
    readonly property color bg:   "#08080a"
    readonly property color bg1:  "#0d0d10"
    readonly property color bg2:  "#111115"
    readonly property color bg3:  "#16161c"
    readonly property color bg4:  "#1c1c24"
    readonly property color bg5:  "#22222c"

    // Borders
    readonly property color border:     "#1e1e28"
    readonly property color border2:    "#2a2a38"
    readonly property color border3:    "#363648"
    readonly property color borderGold: "#6a4e10"

    // Gold
    readonly property color gold:    "#d4a017"
    readonly property color goldL:   "#f0c040"
    readonly property color goldD:   "#8a6510"
    readonly property color goldDim: "#2a2008"
    readonly property color goldMid: "#3a2e0a"

    // Amber
    readonly property color amber:    "#e8961a"
    readonly property color amberL:   "#ffb83a"
    readonly property color amberD:   "#7a4d08"
    readonly property color amberDim: "#1e1608"
    readonly property color amberMid: "#2e2008"

    // Green
    readonly property color green:    "#22c55e"
    readonly property color greenL:   "#4ade80"
    readonly property color greenD:   "#0a4a22"
    readonly property color greenDim: "#0a1e10"
    readonly property color greenMid: "#0e2818"

    // Cyan
    readonly property color cyan:    "#06b6d4"
    readonly property color cyanL:   "#22d3ee"
    readonly property color cyanD:   "#074a5a"
    readonly property color cyanDim: "#061418"
    readonly property color cyanMid: "#081e28"

    // Red
    readonly property color red:    "#ef4444"
    readonly property color redD:   "#450a0a"
    readonly property color redDim: "#160606"
    readonly property color redMid: "#240a0a"

    // Text
    readonly property color tw:  "#f8f8fc"
    readonly property color tg:  "#6060a0"
    readonly property color td:  "#303050"
    readonly property color tdd: "#202038"

    // ═══════════════════════════════════════════════════════════
    //  FONTS
    // ═══════════════════════════════════════════════════════════
    readonly property string brandFamily: "Trebuchet MS"
    readonly property string monoFamily:  "Consolas"
    readonly property string bodyFamily:  "Segoe UI"

    readonly property font brandFont:  Qt.font({family: brandFamily, pixelSize: 26, bold: true})
    readonly property font titleFont:  Qt.font({family: brandFamily, pixelSize: 19, bold: true})
    readonly property font h2Font:     Qt.font({family: brandFamily, pixelSize: 10, bold: true})
    readonly property font bodyFont:   Qt.font({family: bodyFamily,  pixelSize: 16})
    readonly property font smallFont:  Qt.font({family: bodyFamily,  pixelSize: 15})
    readonly property font tinyFont:   Qt.font({family: bodyFamily,  pixelSize: 14})
    readonly property font monoFont:   Qt.font({family: monoFamily,  pixelSize: 16})
    readonly property font monoSFont:  Qt.font({family: monoFamily,  pixelSize: 15})
    readonly property font monoTFont:  Qt.font({family: monoFamily,  pixelSize: 14})
    readonly property font valFont:    Qt.font({family: monoFamily,  pixelSize: 17, bold: true})
    readonly property font bigFont:    Qt.font({family: monoFamily,  pixelSize: 28, bold: true})
    readonly property font navFont:    Qt.font({family: brandFamily, pixelSize: 17})

    // ═══════════════════════════════════════════════════════════
    //  COLOR HELPERS — get pedal colors by prefix
    // ═══════════════════════════════════════════════════════════
    function pedalColor(prefix)    { return prefix === "b" ? amber : prefix === "t" ? green : cyan }
    function pedalColorL(prefix)   { return prefix === "b" ? amberL : prefix === "t" ? greenL : cyanL }
    function pedalColorD(prefix)   { return prefix === "b" ? amberD : prefix === "t" ? greenD : cyanD }
    function pedalColorDim(prefix) { return prefix === "b" ? amberDim : prefix === "t" ? greenDim : cyanDim }
    function pedalColorMid(prefix) { return prefix === "b" ? amberMid : prefix === "t" ? greenMid : cyanMid }

    // ═══════════════════════════════════════════════════════════
    //  ANIMATION
    // ═══════════════════════════════════════════════════════════
    readonly property int animFast:   120
    readonly property int animNormal: 200
    readonly property int animSlow:   350
}
