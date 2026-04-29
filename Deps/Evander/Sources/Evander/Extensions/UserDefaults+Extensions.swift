//  Created by Andromeda on 01/10/2021.
//

#if canImport(UIKit)
import UIKit

public typealias Color = UIColor
#else

import AppKit
public typealias Color = NSColor
#endif

public extension UserDefaults {
    
    func set(_ color: Color?, forKey defaultName: String) {
        guard let data = color?.data else {
            removeObject(forKey: defaultName)
            return
        }
        set(data, forKey: defaultName)
    }
    
    func color(forKey defaultName: String) -> Color? {
        data(forKey: defaultName)?.color
    }
    
    func bool(forKey key: String, fallback: Bool = false) -> Bool {
        self.object(forKey: key) as? Bool ?? fallback
    }

    func integer(forKey key: String, fallback: Int = 0) -> Int {
        self.object(forKey: key) as? Int ?? fallback
    }

    func double(forKey key: String, fallback: Double = 0) -> Double {
        self.object(forKey: key) as? Double ?? fallback
    }
    
    func checkRegister(object: Any, for key: String) {
        if self.data(forKey: key) == nil {
            self.setValue(object, forKey: key)
        }
    }
}

public extension Numeric {
    var data: Data {
        var bytes = self
        return Data(bytes: &bytes, count: MemoryLayout<Self>.size)
    }
}

public extension Data {
    func object<T>() -> T { withUnsafeBytes{$0.load(as: T.self)} }
    var color: Color { .init(data: self) }
}

public extension Color {
    convenience init(data: Data) {
        let size = MemoryLayout<CGFloat>.size
        self.init(red:   data.subdata(in: size*0..<size*1).object(),
                  green: data.subdata(in: size*1..<size*2).object(),
                  blue:  data.subdata(in: size*2..<size*3).object(),
                  alpha: data.subdata(in: size*3..<size*4).object())
    }
    var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var (red, green, blue, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }
    var data: Data? {
        guard let rgba = rgba else { return nil }
        return rgba.red.data + rgba.green.data + rgba.blue.data + rgba.alpha.data
    }
}
