import SwiftUI

struct WakeHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wake from standby")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("MacDroid TV can only turn on a TV that stays reachable on your network while it is off. Enable your TV's quick-start / networked-standby option, then add its Wake-on-LAN MAC in the Devices window.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Group {
                        Text("TCL Google TV")
                            .font(.headline)
                        Text("Settings → System → Power and energy → **Quick start** (On). If present, also enable Settings → Network & Internet → **Network Standby**.")
                    }

                    Group {
                        Text("Sony Bravia")
                            .font(.headline)
                        Text("Settings → Network & Internet → **Remote start** → On (Networked Standby) or On (powered by apps). On some 2020 models, also enable Settings → Network & Internet → Home Network → IP control → **Simple IP control**.")
                    }

                    Group {
                        Text("Hisense Google TV")
                            .font(.headline)
                        Text("Settings → System → Power & Energy → **Fast Power On** or **Quick Start** (On). If present, enable **Network Standby** / **Wake on LAN**.")
                    }

                    Group {
                        Text("Philips")
                            .font(.headline)
                        Text("Settings → Network → **Wake on LAN** / **WoWLAN** (On). On some models WoWLAN only works over Wi-Fi, not Ethernet.")
                    }

                    Group {
                        Text("Sharp Android TV")
                            .font(.headline)
                        Text("Settings → Device Preferences → **Quick Start** (On). Enable **Network Standby** if present.")
                    }

                    Group {
                        Text("Xiaomi / Mi Box")
                            .font(.headline)
                        Text("Settings → Device Preferences / System → Power → **Wake on LAN** or **Networked standby** (On).")
                    }

                    Group {
                        Text("NVIDIA Shield")
                            .font(.headline)
                        Text("Settings → Device Preferences → Power → **Wake on LAN** (On). Alternatively, enable Developer options → **Stay awake**.")
                    }

                    Group {
                        Text("Chromecast / Google TV Streamer")
                            .font(.headline)
                        Text("Settings → System → Power → **Fast boot** or **Always on** (if available). Use the power adapter that came with the device.")
                    }

                    Divider()

                    Text("Tips")
                        .font(.headline)
                    Text("• Ethernet is more reliable than Wi-Fi for standby networking.\n• Give the TV a DHCP reservation so its address does not change.\n• Add the TV's Wake-on-LAN MAC in the Devices window.\n• Some TVs still drop off the network in standby; those can only be switched on with their own remote.")
                        .fixedSize(horizontal: false, vertical: true)

                    Link(
                        "Open the full guide on GitHub",
                        destination: URL(string: "https://github.com/frankt2012/MacDroidTV#wake-on-lan--networked-standby")!
                    )
                    .font(.caption)
                }
                .padding(.trailing, 4)
            }
        }
        .padding(20)
        .frame(width: 500, height: 560)
    }
}
