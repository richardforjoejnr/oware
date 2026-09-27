import Foundation

/// Web pages the app links to (served by GitHub Pages from docs/lelu-oware).
enum Links {
    static let site = URL(string: "https://richardforjoejnr.github.io/oware/lelu-oware/")!
    /// Newsletter sign-up lives on the website so the app never asks for an email address.
    static let newsletter = URL(string: "https://richardforjoejnr.github.io/oware/lelu-oware/newsletter")!
    static let privacy = URL(string: "https://richardforjoejnr.github.io/oware/lelu-oware/privacy")!
}
