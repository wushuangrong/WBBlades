//
//  WBScanLog.swift
//  Pods-WBBladesCrashAnalyzeApp
//
//  Created by 朴惠姝 on 2021/4/22.
//

import Foundation

class WBBMScanSystemLogTool{
    class func checkLogHeader(lines: Array<Substring>, _ lastIndex: UnsafeMutablePointer<Int>,endLine: String) -> Dictionary<String, Any>{
        var detailInfo = String.init("{")
        var lineIndex = 0;
        
        //crash log info
        for suchline in lines {
            lineIndex += 1
            if suchline.count > 0 {
                let lineArray = suchline.split(separator: Character.init(":"))
                let key = lineArray.first ?? ""
                if key == suchline {
                    continue
                }
                detailInfo.append(contentsOf: "\"\(key.trimmingCharacters(in: CharacterSet.whitespaces))\":")
            
                let start = suchline.index(suchline.startIndex, offsetBy: key.count+1)
                let value = String.init(suchline[start..<suchline.endIndex]).replacingOccurrences(of: "\"", with: "“")
                detailInfo.append("\"\(value.trimmingCharacters(in: CharacterSet.whitespaces))\",")
            }
            
            if suchline.hasPrefix(endLine) {
                detailInfo.removeLast()
                break
            }
        }
        detailInfo.append("}")
        
        let jsonData: Data = detailInfo.data(using: .utf8) ?? Data.init()
        let detailInfoDic: Dictionary<String,Any> = try! JSONSerialization.jsonObject(with: jsonData, options: .mutableContainers) as? Dictionary<String,Any> ?? [:]
        
        lastIndex.pointee = lineIndex
        return detailInfoDic
    }
    
    class func checkSystemCrashEndLine(line: String) -> Bool{
        if line.hasSuffix(WBBMSystemLogEndLine.CrashedWithArm64State.rawValue) ||
            line.hasSuffix(WBBMSystemLogEndLine.CrashedWithArm32State.rawValue) ||
            line.hasSuffix(WBBMSystemLogEndLine.BrinaryImages.rawValue) ||
            line.hasPrefix(WBBMSystemLogEndLine.WakeUpPowerStats.rawValue) {
            return true
        }
        return false
    }
    
    //scan symtem crash log's processes' the scope of address
    class func scanSystemProcessAddress(lines: Array<Substring>, processIdentifier: String, processName: String) -> Dictionary<String,Array<String>>{
        var processDic: Dictionary<String,Array<String>> = Dictionary.init()
        for suchline in lines.reversed() {
            let suchString = String(suchline)
            if WBBMScanSystemLogTool.checkSystemCrashEndLine(line: suchString) {
                break;
            }
            let suchArray = suchString.split(separator: Character.init(" "))
            if suchArray.count > 4 && suchArray[1] == "-" {
                var key = String(suchArray[3])
                if key.contains(processIdentifier) {//when the process's name is same as process's identifier in binary images
                    key = processName
                }else if(key.contains("???")){
                    key = processName
                }
                
                let startAddress = WBBMScanLogTool.hexToDecimal(hex: String(suchArray[0]))
                let endAddress = WBBMScanLogTool.hexToDecimal(hex: String(suchArray[2]))
                processDic[key] = [startAddress,endAddress]
            }
        }
        return processDic
    }
    
    class func scanSystemProcessBinaryUUID(lines: Array<Substring>, processIdentifier: String, processName: String) -> Dictionary<String,String>{
        var processDic: Dictionary<String,String> = Dictionary.init()
        for suchline in lines.reversed() {
            let suchString = String(suchline)
            if WBBMScanSystemLogTool.checkSystemCrashEndLine(line: suchString) {
                break;
            }
            let suchArray = suchString.split(separator: Character.init(" "))
            if suchArray.count > 6 {
                var key = String(suchArray[3])
                if key.contains(processIdentifier) {//when the process's name is same as process's identifier in binary images
                    key = processName
                }else if(key.contains("???")){
                    key = processName
                }
                processDic[key] = String(suchArray[5]).replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
            }
        }
        return processDic
    }
    
    //MARK: -
    //MARK: New Crash
    //scan new symtem crash log's processes' the scope of address
    class func scanSystemProcessAddressNewType(detailInfoDic: Dictionary<String,Any>,logDetailModel: WBBMLogDetailModel, uuid: String) -> Array<WBBMSystemLogNewTypeProcessModel>{
        let usedImages = detailInfoDic["usedImages"] as? Array ?? [];
        
        if usedImages.count == 0 {
            return []
        }
        
        if usedImages[0] is Array<Any> {
            return scanSystemProcessNewTypeArray(usedImages: usedImages, detailInfoDic: detailInfoDic, logDetailModel: logDetailModel, uuid: uuid);
        }
        
        if usedImages[0] is Dictionary<String, Any> {
            return scanSystemProcessNewTypeDictionary(usedImages: usedImages,logDetailModel: logDetailModel)
        }
        
        return []
    }
    
    private class func scanSystemProcessNewTypeArray(usedImages:Array<Any>,detailInfoDic: Dictionary<String,Any>,logDetailModel: WBBMLogDetailModel, uuid: String)-> Array<WBBMSystemLogNewTypeProcessModel>{
        var processArray: Array<WBBMSystemLogNewTypeProcessModel> = Array();
        
        var startAdr = 0
        for suchImages in usedImages {
            let images = suchImages as? Array ?? []
            if images.count > 1 {
                let imageUUID = images.first as? String ?? ""
                if imageUUID == uuid{
                    startAdr = images[1] as? Int ?? 0
                    break
                }
            }
        }
        
        guard startAdr > 0 else{
            return processArray
        }
        
        guard let legacyInfo = detailInfoDic["legacyInfo"] as? Dictionary<String,Any> else {
            return processArray
        }
        guard let imageExtraInfo = legacyInfo["imageExtraInfo"] as? Array<Any> else {
            return processArray
        }
        
        for suchExtra in imageExtraInfo {
            guard let imageExtra = suchExtra as? Dictionary<String,Any> else {
                continue
            }
            
            let imageName = imageExtra["name"] as? String ?? ""
            if imageName == logDetailModel.processName || imageName.hasPrefix("?") || imageName == "" {
                let size = imageExtra["size"] as? Int ?? 0
                let startAddress = String(startAdr)
                let endAddress = String(startAdr+size)

                let processModel = WBBMSystemLogNewTypeProcessModel()
                if logDetailModel.processName == processModel.processName && startAdr == 0{
                    logDetailModel.foundedAddress = false
                }
                processModel.processName = imageName;
                processModel.processStartAddress = startAddress
                processModel.processEndAddress = endAddress
                processArray.append(processModel)
            }
        }
        
        return processArray
    }
    
    private class func scanSystemProcessNewTypeDictionary(usedImages:Array<Any>,logDetailModel: WBBMLogDetailModel)-> Array<WBBMSystemLogNewTypeProcessModel>{
        var processArray: Array<WBBMSystemLogNewTypeProcessModel> = Array();
        
        var hasMain = false
        for suchImages in usedImages {
            guard let images = suchImages as? Dictionary<String,Any> else{
                continue
            }
            
            let processModel = WBBMSystemLogNewTypeProcessModel()
            processModel.processName = images["name"] as? String ?? "";
            
            let startAddress = images["base"] as? Int ?? 0
            let size = images["size"] as? Int ?? 0
            if (!hasMain && (logDetailModel.processName == processModel.processName || processModel.processName == "" || processModel.processName.hasPrefix("?"))) && startAddress == 0{
                logDetailModel.foundedAddress = false
                processModel.processName = logDetailModel.processName
            }
            
            processModel.processStartAddress = String(startAddress)
            processModel.processEndAddress = String(startAddress+size)
            if processModel.processName == logDetailModel.processName {
                hasMain = true
            }
            processArray.append(processModel)
        }
        
        return processArray
    }
}


class WBBMScanLogTool{
    //MARK: -
    //MARK: Hex
    class func hexToDecimal(hex: String) -> String {
        var str = hex.uppercased()
        if str.hasPrefix("0X") {
            str.removeFirst(2)
        }
        var sum = 0
        for i in str.utf8 {
            sum = sum * 16 + Int(i) - 48
            if i >= 65 {
                sum -= 7
            }
        }
        return "\(sum)"
    }
    
    class func decimalToHex(decimal: String) -> String {
        guard let decimalInt = Int(decimal) else {
            return ""
        }
        return String(format: "%llX", decimalInt)
    }
}
