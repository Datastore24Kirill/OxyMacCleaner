import AppKit
let dir=URL(fileURLWithPath:"dist/AppIcon.iconset")
try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {for scale in [1,2] {
    let n=size*scale;let image=NSImage(size:NSSize(width:n,height:n));image.lockFocus()
    let rect=NSRect(x:0,y:0,width:n,height:n);let path=NSBezierPath(roundedRect:rect.insetBy(dx:Double(n)*0.035,dy:Double(n)*0.035),xRadius:Double(n)*0.22,yRadius:Double(n)*0.22)
    NSGradient(starting:NSColor(red:0.04,green:0.15,blue:0.21,alpha:1),ending:NSColor(red:0.03,green:0.42,blue:0.39,alpha:1))!.draw(in:path,angle:60)
    let symbol=NSImage(systemSymbolName:"sparkles.rectangle.stack.fill",accessibilityDescription:nil)!.withSymbolConfiguration(.init(pointSize:Double(n)*0.51,weight:.medium))!
    let tinted=NSImage(size:symbol.size);tinted.lockFocus();NSColor(red:0.4,green:1,blue:0.8,alpha:1).set();NSRect(origin:.zero,size:symbol.size).fill();symbol.draw(at:.zero,from:.zero,operation:.destinationIn,fraction:1);tinted.unlockFocus()
    tinted.draw(in:NSRect(x:Double(n)*0.19,y:Double(n)*0.22,width:Double(n)*0.62,height:Double(n)*0.56));image.unlockFocus()
    let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!;try rep.representation(using:.png,properties:[:])!.write(to:dir.appendingPathComponent("icon_\(size)x\(size)\(scale==2 ? "@2x":"").png"))
}}
