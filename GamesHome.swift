import AppKit

/// Borderless AppKit buttons otherwise draw a rectangular cell focus ring.
final class GameActionButton: NSButton {
    override init(frame:NSRect) { super.init(frame:frame); focusRingType = .none }
    required init?(coder:NSCoder) { super.init(coder:coder); focusRingType = .none }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder(); needsDisplay = true; return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder(); needsDisplay = true; return accepted
    }
    override func draw(_ dirtyRect:NSRect) {
        super.draw(dirtyRect)
        if window?.firstResponder === self {
            let radius = max(0,(layer?.cornerRadius ?? 12)-3)
            let ring = NSBezierPath(roundedRect:bounds.insetBy(dx:3,dy:3),xRadius:radius,yRadius:radius)
            NSColor.white.withAlphaComponent(0.95).setStroke(); ring.lineWidth = 2; ring.stroke()
        }
    }
}

final class GameArtwork: NSView {
    var patches = true
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect:NSRect) {
        let box = bounds.insetBy(dx:8,dy:8), u = box.width/6
        NSColor.white.setFill(); NSBezierPath(roundedRect:box,xRadius:20,yRadius:20).fill()
        if patches {
            let tiles:[(CGFloat,CGFloat,CGFloat,CGFloat,NSColor)] = [
                (0,0,2,2,.systemOrange),(2,0,4,2,.systemTeal),(0,2,2,4,.systemBlue),
                (2,2,2,2,.systemPurple),(4,2,2,4,.systemPink),(2,4,2,2,.systemYellow)]
            for (x,y,w,h,c) in tiles {
                c.withAlphaComponent(0.82).setFill()
                NSBezierPath(roundedRect:NSRect(x:box.minX+x*u+3,y:box.minY+y*u+3,width:w*u-6,height:h*u-6),xRadius:9,yRadius:9).fill()
            }
        } else {
            NSColor(calibratedWhite:0.90,alpha:1).setStroke()
            let grid = NSBezierPath()
            for i in 1..<6 {
                grid.move(to:NSPoint(x:box.minX+CGFloat(i)*u,y:box.minY)); grid.line(to:NSPoint(x:box.minX+CGFloat(i)*u,y:box.maxY))
                grid.move(to:NSPoint(x:box.minX,y:box.minY+CGFloat(i)*u)); grid.line(to:NSPoint(x:box.maxX,y:box.minY+CGFloat(i)*u))
            }; grid.stroke()
            let path = NSBezierPath(); path.lineWidth = u*0.48; path.lineCapStyle = .round; path.lineJoinStyle = .round
            for (i,p) in [(0.5,4.5),(2.5,4.5),(2.5,2.5),(0.5,2.5),(0.5,0.5),(4.5,0.5),(4.5,4.5)].enumerated() {
                let point = NSPoint(x:box.minX+p.0*u,y:box.minY+p.1*u)
                if i == 0 { path.move(to:point) } else { path.line(to:point) }
            }
            NSColor.systemOrange.setStroke(); path.stroke()
        }
    }
}

final class GamesHome: NSView {
    var onZip:(() -> Void)?
    var onPatches:(() -> Void)?
    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer = true; layer?.backgroundColor = NSColor(calibratedRed:0.96,green:0.965,blue:0.975,alpha:1).cgColor
        func label(_ text:String,_ size:CGFloat,_ weight:NSFont.Weight,_ rect:NSRect) {
            let view = NSTextField(labelWithString:text); view.font = .systemFont(ofSize:size,weight:weight); view.frame = rect; addSubview(view)
        }
        label("YOUR DAILY RESET",11,.semibold,NSRect(x:42,y:730,width:400,height:20))
        label("LinkedInGames",36,.bold,NSRect(x:42,y:677,width:560,height:48))
        label("A little focus. A fresh perspective.",17,.regular,NSRect(x:42,y:641,width:560,height:28))
        for (i,name) in ["Zip","Patches"].enumerated() {
            let y:CGFloat = i == 0 ? 366 : 116
            let card = NSView(frame:NSRect(x:36,y:y,width:588,height:224)); card.wantsLayer = true
            card.layer?.backgroundColor = NSColor.white.cgColor; card.layer?.cornerRadius = 24
            addSubview(card)
            let art = GameArtwork(frame:NSRect(x:22,y:30,width:164,height:164)); art.patches = i == 1; card.addSubview(art)
            let title = NSTextField(labelWithString:name); title.font = .systemFont(ofSize:28,weight:.bold); title.frame = NSRect(x:210,y:157,width:300,height:37); card.addSubview(title)
            let detail = NSTextField(wrappingLabelWithString:i == 0 ? "One continuous path.\nEvery square, in order." : "A place for every piece.\nTurn clues into a perfect fit.")
            detail.font = .systemFont(ofSize:16); detail.textColor = .secondaryLabelColor; detail.frame = NSRect(x:210,y:89,width:340,height:56); card.addSubview(detail)
            let button = GameActionButton(title:"Open \(name)  →",target:self,action:i == 0 ? #selector(openZip) : #selector(openPatches))
            button.isBordered = false; button.wantsLayer = true; button.layer?.cornerRadius = 12
            button.layer?.backgroundColor = (i == 0 ? NSColor.systemOrange : NSColor.systemTeal).cgColor
            button.contentTintColor = .white; button.font = .systemFont(ofSize:15,weight:.semibold)
            button.frame = NSRect(x:210,y:30,width:174,height:42); card.addSubview(button)
        }
        label("Your pace. Your progress. Pick up where you left off.",13,.regular,NSRect(x:42,y:60,width:580,height:24))
    }
    required init?(coder:NSCoder) { fatalError() }
    @objc private func openZip() { onZip?() }
    @objc private func openPatches() { onPatches?() }
}

func gamesIcon() -> NSImage {
    NSImage(size:NSSize(width:512,height:512),flipped:false) { bounds in
        NSColor(calibratedRed:0.09,green:0.15,blue:0.25,alpha:1).setFill()
        NSBezierPath(roundedRect:bounds.insetBy(dx:12,dy:12),xRadius:108,yRadius:108).fill()
        let colors:[NSColor] = [.systemOrange,.systemTeal,.systemBlue,.systemPurple]
        let boxes = [NSRect(x:70,y:270,width:172,height:172),NSRect(x:270,y:270,width:172,height:172),NSRect(x:70,y:70,width:172,height:172),NSRect(x:270,y:70,width:172,height:172)]
        for (c,r) in zip(colors,boxes) { c.setFill(); NSBezierPath(roundedRect:r,xRadius:36,yRadius:36).fill() }
        return true
    }
}
