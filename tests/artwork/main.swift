import AppKit
import CoreGraphics
import ImageIO
import QuartzCore

let args=CommandLine.arguments
let character=ArtworkCharacter(rawValue:args.count>1 ? args[1] : "hood") ?? .hood
let out=URL(fileURLWithPath:args.count>2 ? args[2] : "/private/tmp/kurocat-artwork-review")
try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
UserDefaults.standard.setVolatileDomain([
    "KuroCat.ArtworkCharacter":character.rawValue,
    "KuroCat.ShowKeyBadges":false,"KuroCat.ShowMouseBadges":false,
    "KuroCat.PetInteraction":true,"KuroCat.TabletMode":2,
    "KuroCat.CustomSkin":"","KuroCat.ShowKeyLegends":false
],forName:UserDefaults.argumentDomain)

precondition(ArtworkKeyboardLayout.keycaps.count==68,"Expected 68 keys")
precondition(Set(ArtworkKeyboardLayout.keycaps.map(\.key)).count==68,"Duplicate physical keys")
precondition((0..<5).map {row in ArtworkKeyboardLayout.keycaps.filter{$0.row==row}.count} == [15,15,14,14,10])
for key in [PhysicalKey.home,.pageUp,.pageDown,.fn,.forwardDelete] {
    precondition(ArtworkKeyboardLayout.lookup[key] != nil,"Missing nav key")
}
precondition(PhysicalKey.fromHIDUsage(0x4A) == .home)
precondition(PhysicalKey.fromCGKeyCode(116) == .pageUp)
precondition(PhysicalKey.fromCGKeyCode(121) == .pageDown)
precondition(ArtworkRenderer.image(character) != nil,"Artwork missing")
precondition(Set(ArtworkKeyboardLayout.keycaps.map { "\(KeyboardLayout.canvasPoint(for:$0.key).x),\(KeyboardLayout.canvasPoint(for:$0.key).y)" }).count == 68, "Every artwork key needs a distinct native paw target")
let f=ArtworkRenderer.profile(character)
precondition(f.mouse.x<f.keyboard.minX,"Mouse must be on viewer-left")
precondition(ArtworkRenderer.keyPoint(.space,character:character).y < ArtworkRenderer.keyPoint(.k1,character:character).y)
precondition(character == .hood || !f.hasLegs)

func input(_ t:Double,keys:[PhysicalKey]=[],velocity:CGVector = .zero,idle:Double=0,kpm:CGFloat=0)->ScriptedFrameInput {
    ScriptedFrameInput(now:1000+t,activeKeys:Set(keys),orderedKeys:keys,
        mouseScreenPos:CGPoint(x:184,y:196),mouseVelocity:velocity,leftMouseDown:false,rightMouseDown:false,
        lastMouseMoveTime:1000-idle,lastMouseClickTime:1000-idle,lastKeyActivityTime:1000-idle,kpm:kpm)
}
func step(_ p:CatPhysics,_ t:Double,_ i:ScriptedFrameInput) {
    p.step(dt:1/60,windowFrameInScreen:CGRect(x:0,y:0,width:360,height:320),scripted:i)
}
func render(_ p:CatPhysics)->CGImage {
    let c=CGContext(data:nil,width:720,height:640,bitsPerComponent:8,bytesPerRow:720*4,
        space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x:0,y:640);c.scaleBy(x:2,y:-2)
    CatRenderer.draw(in:c,physics:p,showPermissionPill:false)
    return c.makeImage()!
}
func png(_ image:CGImage,_ name:String) {
    let url=out.appendingPathComponent(character.rawValue+"-"+name+".png")
    let d=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil)!
    CGImageDestinationAddImage(d,image,nil);precondition(CGImageDestinationFinalize(d))
}

func pixel(_ image:CGImage,_ point:CGPoint)->[UInt8] {
    let x=min(image.width-1,max(0,Int(point.x))),y=min(image.height-1,max(0,Int(point.y)))
    guard let cropped=image.cropping(to:CGRect(x:x,y:y,width:1,height:1)),let data=cropped.dataProvider?.data,
          let bytes=CFDataGetBytePtr(data) else {return [0,0,0,0]}
    return Array(UnsafeBufferPointer(start:bytes,count:4))
}
func canvasPoint(_ q:CGPoint)->CGPoint {
    let rect=ArtworkRenderer.stageRect(ArtworkRenderer.image(character)!)
    return CGPoint(x:(rect.minX+q.x*rect.width)*2,y:(rect.minY+q.y*rect.height)*2)
}

var report:[[String:Any]]=[]
let names=["idle","typing","mouse","gaming","blink","yawn","pet-head","pet-body","hunt","pickup","dizzy","sleep","fast-typing"]
for name in names {
    let p=CatPhysics()
    let duration:Double = name == "sleep" ? 82 : name == "dizzy" ? 12 : name == "blink" ? 3.28 : name == "yawn" ? 0.9 : 2
    let n=Int(duration*60)
    var prior:[PhysicalKey]=[]
    for tick in 0..<n {
        let t=Double(tick)/60
        var i=input(t,idle:2)
        switch name {
        case "typing":
            let key:PhysicalKey=Int(t*7)%2==0 ? .a : .j
            i=input(t,keys:[key],idle:2)
            if prior != [key] {p.triggerKeyDown(key,at:1000+t)}
            prior=[key]
        case "gaming":
            i=input(t,keys:[.w,.a,.leftShift],velocity:CGVector(dx:260,dy:50),idle:2)
            i.lastMouseMoveTime=i.now
            if tick==0 {for key in i.orderedKeys {p.triggerKeyDown(key,at:1000+t)}}
        case "mouse":
            i=input(t,velocity:CGVector(dx:260,dy:0),idle:2);i.lastMouseMoveTime=i.now
            i.leftMouseDown=true
            if tick==0 {p.triggerMouseClick(button:0,isDown:true)}
        case "yawn": i=input(t,idle:44)
        case "sleep": i=input(t)
        case "hunt","dizzy": i=input(t,velocity:CGVector(dx:3600,dy:0),idle:2);i.lastMouseMoveTime=i.now
        case "pickup": p.setDragging(true,dragDx:sin(t*4)*8)
        case "pet-head","pet-body":
            if tick%3==0 {p.registerPetStroke(canvasPoint:CGPoint(x:184,y:125),delta:0,isHead:name == "pet-head",at:1000+t)}
        case "fast-typing": i=input(t,keys:[.a,.j],idle:2,kpm:360)
        default:break
        }
        step(p,t,i)
    }
    precondition(p.hindFootActive.value<0.001,"Artwork must never grow an extra foot")
    precondition(p.tailTyping.value<0.001,"Artwork tail is not an extra keyboard limb")
    switch name {
    case "typing":precondition(p.leftPawTyping || p.rightPawTyping)
    case "gaming":
        precondition(p.leftPawOnMouse && p.rightPawTyping,"WASD + mouse must not cross arms")
        let mouse=ArtworkRenderer.wrist(true,physics:p,character:character)
        let key=ArtworkRenderer.wrist(false,physics:p,character:character)
        let shift=ArtworkRenderer.keyPoint(.leftShift,character:character)
        precondition(abs(mouse.x-f.mouse.x)<0.03,"Visible paw must reach the mouse")
        precondition(hypot(key.x-shift.x,key.y-shift.y)<0.02,"Visible paw must reach the actual held key")
    case "mouse":
        precondition(p.leftPawOnMouse && p.mousePressLeft.value>0.8)
        let wrist=ArtworkRenderer.wrist(true,physics:p,character:character)
        precondition(hypot(wrist.x-f.mouse.x,wrist.y-f.mouse.y)<0.03,"Mouse response must move the visible paw")
    case "blink":precondition(p.effectiveEyeClosure>0.4)
    case "yawn":precondition(p.yawnAmount>0.9)
    case "pet-head":precondition(p.effectiveEyeClosure>0.9)
    case "pet-body":precondition(p.petBodyIntensity>0.6)
    case "hunt":precondition(p.huntIntensity.value>0.8)
    case "pickup":precondition(p.scruffDrag.value>0.9)
    case "dizzy":precondition(p.dizzyIntensity.value>0.5)
    case "sleep":precondition(p.sleepiness>0.9 && p.lieIntensity.value>0.8)
    case "fast-typing":precondition(p.angerIntensity.value>0.5)
    default:break
    }
    let start=CACurrentMediaTime();let image=render(p);let ms=(CACurrentMediaTime()-start)*1000
    if character == .hood && name == "idle" {
        let below=canvasPoint(CGPoint(x:0.47,y:0.915))
        precondition(pixel(image,below)[3]<10,"Torso must not protrude below the keyboard between the feet")
    }
    if character == .blob && name == "mouse" {
        let s=ArtworkRenderer.deform(CGPoint(x:0.195,y:0.505),physics:p,profile:f)
        let e=ArtworkRenderer.wrist(true,physics:p,character:character)
        let color=pixel(image,canvasPoint(CGPoint(x:(s.x+e.x)/2-0.0125,y:(s.y+e.y)/2-0.0075)))
        precondition(color[0]>220 && color[1]<212 && color[2]>65,"Arm must share the body's golden material, not lemon yellow")
    }
    png(image,name)
    report.append(["action":name,"nativeSimulationSeconds":duration,"renderMs":ms,"backend":ArtworkRenderer.lastBackend,
        "eyeClosure":Double(p.effectiveEyeClosure),"yawn":Double(p.yawnAmount),
        "hunt":Double(p.huntIntensity.value),"dizzy":Double(p.dizzyIntensity.value),
        "sleep":Double(p.sleepiness),"pickup":Double(p.scruffDrag.value),
        "leftPawOnMouse":p.leftPawOnMouse,"rightPawTyping":p.rightPawTyping,
        "extraFoot":Double(p.hindFootActive.value)])
}

// An actual native 3-second replay, not an image-generation animation.
let p=CatPhysics(), gifURL=out.appendingPathComponent(character.rawValue+"-native-demo.gif")
let gif=CGImageDestinationCreateWithURL(gifURL as CFURL,"com.compuserve.gif" as CFString,30,nil)!
CGImageDestinationSetProperties(gif,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
var prior:PhysicalKey?=nil
for tick in 0..<180 {
    let t=Double(tick)/60, key:PhysicalKey=Int(t*6)%2==0 ? .a : .j
    let typing=t<1.8
    if typing && key != prior {p.triggerKeyDown(key,at:1000+t);prior=key}
    if !typing && tick%3==0 {p.registerPetStroke(canvasPoint:CGPoint(x:184,y:125),delta:0,isHead:true,at:1000+t)}
    step(p,t,input(t,keys:typing ? [key] : [],idle:2))
    if tick%6==0 {
        CGImageDestinationAddImage(gif,render(p),[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.1]] as CFDictionary)
    }
}
precondition(CGImageDestinationFinalize(gif))

// Regression: both extreme drag directions retain the painted ear tips inside the window.
for swing:CGFloat in [-0.34,0.34] {
    let p=CatPhysics();p.setDragging(true)
    for tick in 0..<90 {step(p,Double(tick)/60,input(Double(tick)/60,idle:10))}
    p.scruffSwing.value=swing
    let image=render(p)
    let tips=character == .hood ? [CGPoint(x:0.27,y:0.096),CGPoint(x:0.74,y:0.096)]
        : [CGPoint(x:0.30,y:0.089),CGPoint(x:0.68,y:0.090)]
    for tip in tips {
        let target=canvasPoint(ArtworkRenderer.deform(tip,physics:p,profile:f))
        precondition(target.y>8 && target.x>8 && target.x<712,"Drag must reserve room around both ears")
        var alpha:UInt8=0
        for dx in -2...2 {for dy in -2...2 {
            alpha=max(alpha,pixel(image,CGPoint(x:target.x+CGFloat(dx),y:target.y+CGFloat(dy)))[3])
        }}
        precondition(alpha>80,"Painted ear tip was cropped from the drag texture")
    }
    png(image,swing<0 ? "drag-left-v2" : "drag-right-v2")
}
let dragP=CatPhysics(),dragURL=out.appendingPathComponent(character.rawValue+"-drag-v2.gif")
let dragGIF=CGImageDestinationCreateWithURL(dragURL as CFURL,"com.compuserve.gif" as CFString,52,nil)!
CGImageDestinationSetProperties(dragGIF,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
var wasDragging=false
for tick in 0..<312 {
    let t=Double(tick)/60,dragging=t>=0.6 && t<3.2
    if dragging {dragP.setDragging(true,dragDx:sin((t-0.6)*3)*14)}
    else if wasDragging {dragP.setDragging(false)}
    wasDragging=dragging
    step(dragP,t,input(t,idle:10))
    if tick%6==0 {
        CGImageDestinationAddImage(dragGIF,render(dragP),[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.1]] as CFDictionary)
    }
}
precondition(CGImageDestinationFinalize(dragGIF))
try JSONSerialization.data(withJSONObject:["character":character.rawValue,"keyCount":68,"actions":report,
    "regressions":["torsoOcclusion":character == .hood ? "passed" : "not-applicable",
        "goldArmMaterial":character == .blob ? "passed" : "not-applicable","dragEarTips":"passed"],"dragGifFrames":52],options:[.prettyPrinted,.sortedKeys])
    .write(to:out.appendingPathComponent(character.rawValue+"-test-report.json"))
print("PASS \(character.rawValue): 68-key mapping, 13 native action scenarios, no extra limbs, torso/material/ear regressions, native typing and pickup/release GIFs")
