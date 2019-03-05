// SPDX-License-Identifier: MIT
// Copyright © 2018-2019 WireGuard LLC. All Rights Reserved.

import Foundation

class TunnelImporter {
    static func importFromFile(urls: [URL], into tunnelsManager: TunnelsManager, sourceVC: AnyObject?, errorPresenterType: ErrorPresenterProtocol.Type, completionHandler: (() -> Void)? = nil) {
        guard !urls.isEmpty else {
            completionHandler?()
            return
        }
        let dispatchGroup = DispatchGroup()
        var configs = [TunnelConfiguration?]()
        var lastFileImportErrorText: (title: String, message: String)?
        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                dispatchGroup.enter()
                ZipImporter.importConfigFiles(from: url) { result in
                    if let error = result.error {
                        lastFileImportErrorText = error.alertText
                    }
                    if let configsInZip = result.value {
                        configs.append(contentsOf: configsInZip)
                    }
                    dispatchGroup.leave()
                }
            } else { /* if it is not a zip, we assume it is a conf */
                let fileName = url.lastPathComponent
                let fileBaseName = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                dispatchGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let fileContents: String
                    do {
                        fileContents = try String(contentsOf: url)
                    } catch let error {
                        if let cocoaError = error as? CocoaError, cocoaError.isFileError {
                            lastFileImportErrorText = (title: tr("alertCantOpenInputConfFileTitle"), message: error.localizedDescription)
                        } else {
                            lastFileImportErrorText = (title: tr("alertCantOpenInputConfFileTitle"), message: tr(format: "alertCantOpenInputConfFileMessage (%@)", fileName))
                        }
                        DispatchQueue.main.async {
                            configs.append(nil)
                            dispatchGroup.leave()
                        }
                        return
                    }
                    let tunnelConfiguration = try? TunnelConfiguration(fromWgQuickConfig: fileContents, called: fileBaseName)
                    if tunnelConfiguration == nil {
                        lastFileImportErrorText = (title: tr("alertBadConfigImportTitle"), message: tr(format: "alertBadConfigImportMessage (%@)", fileName))
                    }
                    DispatchQueue.main.async {
                        configs.append(tunnelConfiguration)
                        dispatchGroup.leave()
                    }
                }
            }
        }
        dispatchGroup.notify(queue: .main) {
            tunnelsManager.addMultiple(tunnelConfigurations: configs.compactMap { $0 }) { numberSuccessful, lastAddError in
                if !configs.isEmpty && numberSuccessful == configs.count {
                    completionHandler?()
                    return
                }
                let alertText: (title: String, message: String)?
                if urls.count == 1 {
                    if urls.first!.pathExtension.lowercased() == "zip" && !configs.isEmpty {
                        alertText = (title: tr(format: "alertImportedFromZipTitle (%d)", numberSuccessful),
                                     message: tr(format: "alertImportedFromZipMessage (%1$d of %2$d)", numberSuccessful, configs.count))
                    } else {
                        alertText = lastFileImportErrorText ?? lastAddError?.alertText
                    }
                } else {
                    alertText = (title: tr(format: "alertImportedFromMultipleFilesTitle (%d)", numberSuccessful),
                                 message: tr(format: "alertImportedFromMultipleFilesMessage (%1$d of %2$d)", numberSuccessful, configs.count))
                }
                if let alertText = alertText {
                    errorPresenterType.showErrorAlert(title: alertText.title, message: alertText.message, from: sourceVC, onPresented: completionHandler)
                } else {
                    completionHandler?()
                }
            }
        }
    }
}
