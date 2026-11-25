import AppKit
import CoreGraphics
import ImageIO
import CoreImage

enum ArtworkCharacter: String, CaseIterable {
    case none, hood, blob
    var title: String {
        switch self {
        case .none: return "原生矢量猫"
        case .hood: return "大喵 · 黄斗篷与粉白键盘"
        case .blob: return "奶咪 · 绿眼睛与黄绿键盘"
        }
    }
}

/// An artwork renderer driven by CatPhysics, not a replacement input/animation engine.
/// Images remain immutable. A small continuous texture rig preserves the approved silhouette
/// while the native springs drive breathing, typing, tracking, pickup and tail reactions.
enum ArtworkRenderer {
    struct Profile {
        let character: ArtworkCharacter
        let head: CGPoint
        let leftEye: CGRect
        let rightEye: CGRect
        let faceSample: CGRect
        let mouth: CGRect
        let leftWrist: CGPoint
        let rightWrist: CGPoint
        let keyboard: CGRect
        let mouse: CGPoint
        let tail: CGPoint
        var hasLegs: Bool { character == .hood }
        var ink: CGColor {
            character == .hood ? CGColor(red: 0.56, green: 0.29, blue: 0.21, alpha: 1)
                : CGColor(red: 0.35, green: 0.29, blue: 0.10, alpha: 1)
        }
    }

    static func profile(_ character: ArtworkCharacter) -> Profile {
        if character == .hood {
            return Profile(character: character, head: CGPoint(x: 0.47, y: 0.35),
                leftEye: CGRect(x: 0.284, y: 0.312, width: 0.137, height: 0.110),
                rightEye: CGRect(x: 0.526, y: 0.312, width: 0.137, height: 0.110),
                faceSample: CGRect(x: 0.445, y: 0.462, width: 0.05, height: 0.025),
                mouth: CGRect(x: 0.418, y: 0.402, width: 0.113, height: 0.032),
                leftWrist: CGPoint(x: 0.36, y: 0.707), rightWrist: CGPoint(x: 0.565, y: 0.707),
                keyboard: CGRect(x: 0.178, y: 0.714, width: 0.599, height: 0.140),
                mouse: CGPoint(x: 0.083, y: 0.792), tail: CGPoint(x: 0.83, y: 0.55))
        }
        return Profile(character: character, head: CGPoint(x: 0.485, y: 0.26),
            leftEye: CGRect(x: 0.299, y: 0.191, width: 0.118, height: 0.086),
            rightEye: CGRect(x: 0.553, y: 0.191, width: 0.118, height: 0.086),
            faceSample: CGRect(x: 0.46, y: 0.348, width: 0.06, height: 0.028),
            mouth: CGRect(x: 0.394, y: 0.298, width: 0.187, height: 0.030),
            leftWrist: CGPoint(x: 0.23, y: 0.577), rightWrist: CGPoint(x: 0.735, y: 0.577),
            keyboard: CGRect(x: 0.195, y: 0.820, width: 0.684, height: 0.135),
            mouse: CGPoint(x: 0.10, y: 0.90), tail: CGPoint(x: 0.87, y: 0.72))
    }

    private static var images: [ArtworkCharacter: CGImage] = [:]
    private static var bodyImages: [ArtworkCharacter: CGImage] = [:]
    private static var patches: [String: CGImage] = [:]
    private static var textures: [ArtworkCharacter: CIImage] = [:]
    private static var rigBitmaps: [ArtworkCharacter: CGImage] = [:]
    private static var warpRects: [ArtworkCharacter: CGRect] = [:]
    private(set) static var lastBackend="uninitialized"
    private static let ciContext=CIContext(options:[.cacheIntermediates:true])
    private static let warp=CIWarpKernel(source:"""
    float bump(vec2 p, vec2 c, float r) { vec2 d=p-c; return exp(-dot(d,d)/(r*r)); }
    vec2 forward(vec2 q,vec2 head,vec2 lw,vec2 rw,vec4 kb,vec2 tail,float legs,
        vec4 a,vec4 b,vec4 c,vec4 arms,vec4 extras,vec2 gaze) {
        if(legs>0.5) {
            float compact=smoothstep(0.60,0.74,q.y)*(1.-smoothstep(0.73,0.82,q.x));
            q.x=0.47+(q.x-0.47)*(1.-0.16*compact);
            q.y=0.60+(q.y-0.60)*(1.-0.17*compact);
        }
        bool eq=(q.x>kb.x-0.025 && q.x<kb.x+kb.z+0.025 && q.y>kb.y-0.008 && q.y<kb.y+kb.w+0.008)
            || (q.x<0.17 && q.y>0.70);
        float lh=bump(q,lw,legs>0.5 ? 0.07 : 0.10),rh=bump(q,rw,legs>0.5 ? 0.07 : 0.10);
        float hw=legs>0.5 ? 1.-smoothstep(0.51,0.60,q.y) : bump(q,head,0.30);
        float bw=1.-smoothstep(0.98,1.,q.y);
        float fw=(legs>0.5 && q.y>0.875 && q.x>0.23 && q.x<0.69) ? 1. : 0.;
        float w=max(bw,fw);
        vec2 seat=vec2(0.48,mix(legs>0.5 ? 0.72 : 0.80,legs>0.5 ? 0.54 : 0.38,b.y));
        float roll=clamp(a.y,-0.12,0.12)*(legs>0.5 ? 0.30 : 0.15)*hw
            +clamp(b.z,-0.20,0.20)*b.y*0.24*w+sin(c.y)*c.x*0.035*w+b.w*0.045*w;
        vec2 d=q-seat;
        vec2 v=seat+vec2(d.x*cos(roll)-d.y*sin(roll),d.x*sin(roll)+d.y*cos(roll));
        v.x+=clamp(a.x,-16.,16.)*0.0005*w+clamp(a.z,-1.,1.)*(legs>0.5 ? 0.009 : 0.004)*hw;
        v.y+=b.x*0.00065*w+clamp(a.w,-20.,20.)*mix(0.0007,0.00035,b.y)*hw+(b.w*0.032-b.y*0.04)*w;
        v.y+=(q.y-seat.y)*clamp(c.z-1.,-0.045,0.045)*w;
        float ew=(1.-smoothstep(0.21,0.29,q.y))*smoothstep(0.08,0.17,abs(q.x-head.x));
        v.y+=clamp(extras.z,0.,1.)*0.009*ew; v.x+=extras.w*0.0008*ew;
        vec2 e1=legs>0.5 ? vec2(0.3525,0.367) : vec2(0.358,0.234);
        vec2 e2=legs>0.5 ? vec2(0.5945,0.367) : vec2(0.612,0.234);
        float eyes=bump(q,e1,0.07)+bump(q,e2,0.07);
        v+=gaze*vec2(0.002,0.0015)*eyes;
        // Forearms are separate native paths, so they cannot pull the cape or hardware.
        {
            float tw=smoothstep(0.72,0.85,q.x)*bump(q,tail,0.22);
            v.x+=(sin(c.w)*0.012+clamp(extras.x,-36.,36.)*0.0004)*tw;
            v.y+=(cos(c.w*1.3)*0.006+b.y*0.020)*tw;
        }
        if(legs>0.5) v.x+=(0.47-v.x)*0.10*b.y*smoothstep(0.80,0.87,q.y);
        return v;
    }
    kernel vec2 artwork(vec2 size,vec2 head,vec2 lw,vec2 rw,vec4 kb,vec2 tail,float legs,
        vec4 a,vec4 b,vec4 c,vec4 arms,vec4 extras,vec2 gaze) {
        vec2 d=destCoord()/size; d.y=1.-d.y;
        vec2 q=d;
        q=d-(forward(q,head,lw,rw,kb,tail,legs,a,b,c,arms,extras,gaze)-q);
        q=d-(forward(q,head,lw,rw,kb,tail,legs,a,b,c,arms,extras,gaze)-q);
        q=d-(forward(q,head,lw,rw,kb,tail,legs,a,b,c,arms,extras,gaze)-q);
        return vec2(q.x,1.-q.y)*size;
    }
    """)

    private static func warpedImage(_ image:CGImage,physics p:CatPhysics,profile f:Profile)->CGImage? {
        guard let warp=warp else {return nil}
        let scale:CGFloat=512/CGFloat(image.height)
        if textures[f.character] == nil {
            textures[f.character]=CIImage(cgImage:rigBitmap(image,profile:f)).transformed(by:CGAffineTransform(scaleX:scale,y:scale))
        }
        guard let input=textures[f.character] else {return nil}
        func v(_ p:CGPoint)->CIVector {CIVector(x:p.x,y:p.y)}
        let lp=p.leftPaw.point,rp=p.rightPaw.point
        let arguments:[Any]=[
            CIVector(x:input.extent.width,y:input.extent.height),v(f.head),v(f.leftWrist),v(f.rightWrist),
            CIVector(x:f.keyboard.minX,y:f.keyboard.minY,z:f.keyboard.width,w:f.keyboard.height),v(f.tail),f.hasLegs ? 1.0 : 0.0,
            CIVector(x:p.bodyShiftX.value,y:p.headTilt.value,z:p.headYaw.value,w:p.headOffsetY.value),
            CIVector(x:p.breathingOffset,y:clamp(p.scruffDrag.value,0,1),z:p.scruffSwing.value,w:clamp(p.lieIntensity.value,0,1)),
            CIVector(x:clamp(p.dizzyIntensity.value,0,1),y:p.dizzyPhase,z:p.bodySquash.value,w:p.tailPhase),
            CIVector(x:clamp((lp.x-CatPhysics.leftPawRest.x)/360,-0.11,0.055),y:clamp((lp.y-CatPhysics.leftPawRest.y)/320,-0.025,f.hasLegs ? 0.055 : 0.13),
                     z:clamp((rp.x-CatPhysics.rightPawRest.x)/360,-0.055,0.055),w:clamp((rp.y-CatPhysics.rightPawRest.y)/320,-0.025,f.hasLegs ? 0.055 : 0.13)),
            CIVector(x:p.tailFlick.point.x,y:p.tailFlick.point.y,z:p.earFold.value,w:p.earTwitch.value),v(p.eyeGaze.point)
        ]
        let extent=input.extent.insetBy(dx:-input.extent.width*0.12,dy:-input.extent.height*0.12).integral
        guard let result=warp.apply(extent:extent,roiCallback:{_,r in r.insetBy(dx:-250,dy:-250)},image:input,arguments:arguments) else {return nil}
        let rendered=ciContext.createCGImage(result,from:extent)
        warpRects[f.character]=CGRect(x:extent.minX/input.extent.width,y:1-extent.maxY/input.extent.height,
                                      width:extent.width/input.extent.width,height:extent.height/input.extent.height)
        if rendered != nil {lastBackend="CoreImage"}
        return rendered
    }

    static func image(_ character: ArtworkCharacter) -> CGImage? {
        if let image = images[character] { return image }
        let root = ProcessInfo.processInfo.environment["KUROCAT_ART_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? Bundle.main.resourceURL?.appendingPathComponent("CustomCharacters")
        guard let url = root?.appendingPathComponent(character.rawValue + ".png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        images[character] = image
        return image
    }

    private static func bodyImage(_ character:ArtworkCharacter)->CGImage? {
        if let cached=bodyImages[character] {return cached}
        let root=ProcessInfo.processInfo.environment["KUROCAT_ART_ROOT"].map {URL(fileURLWithPath:$0)}
            ?? Bundle.main.resourceURL?.appendingPathComponent("CustomCharacters")
        guard let url=root?.appendingPathComponent(character.rawValue+"-body.png"),
              let source=CGImageSourceCreateWithURL(url as CFURL,nil),
              let image=CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1200
              ] as CFDictionary) else {return nil}
        bodyImages[character]=image
        return image
    }

    static func stageRect(_ image: CGImage) -> CGRect {
        let height: CGFloat = 270
        let width = height * CGFloat(image.width) / CGFloat(image.height)
        return CGRect(x: (360 - width) / 2, y: 20, width: width, height: height)
    }

    private static func clamp(_ x: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(b, max(a, x)) }
    private static func smooth(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = clamp((x - a) / (b - a), 0, 1)
        return t * t * (3 - 2 * t)
    }
    private static func bump(_ p: CGPoint, _ c: CGPoint, _ r: CGFloat) -> CGFloat {
        exp(-((p.x-c.x)*(p.x-c.x)+(p.y-c.y)*(p.y-c.y))/(r*r))
    }

    /// Source points and destinations are normalized in the immutable reference artwork.
    static func deform(_ original: CGPoint, physics p: CatPhysics, profile f: Profile) -> CGPoint {
        var q=original
        if f.hasLegs {
            let compact=smooth(0.60,0.74,q.y)*(1-smooth(0.73,0.82,q.x))
            q.x=0.47+(q.x-0.47)*(1-0.16*compact)
            q.y=0.60+(q.y-0.60)*(1-0.17*compact)
        }
        let scruff = clamp(p.scruffDrag.value, 0, 1)
        let lie = clamp(p.lieIntensity.value, 0, 1)
        let dizzy = clamp(p.dizzyIntensity.value, 0, 1)

        // Do not turn a legless blob into the upstream cat's long-necked silhouette.
        let headWeight = f.hasLegs ? 1 - smooth(0.51, 0.60, q.y) : bump(q, f.head, 0.30)
        let bodyWeight = 1 - smooth(0.98, 1, q.y)
        let footWeight: CGFloat = f.hasLegs && q.y > 0.875 && q.x > 0.23 && q.x < 0.69 ? 1 : 0
        let weight = max(bodyWeight, footWeight)
        let seat = CGPoint(x: 0.48, y: (f.hasLegs ? 0.72 : 0.80)*(1-scruff)+(f.hasLegs ? 0.54 : 0.38)*scruff)
        let roll = clamp(p.headTilt.value, -0.12, 0.12) * (f.hasLegs ? 0.30 : 0.15) * headWeight
            + clamp(p.scruffSwing.value, -0.20, 0.20) * scruff * 0.24 * weight
            + sin(p.dizzyPhase) * dizzy * 0.035 * weight
            + lie * 0.045 * weight
        let cx = q.x-seat.x, cy = q.y-seat.y
        var v = CGPoint(x: seat.x+cx*cos(roll)-cy*sin(roll), y: seat.y+cx*sin(roll)+cy*cos(roll))
        v.x += clamp(p.bodyShiftX.value, -16, 16) * 0.0005 * weight
        v.x += clamp(p.headYaw.value, -1, 1) * (f.hasLegs ? 0.009 : 0.004) * headWeight
        v.y += p.breathingOffset * 0.00065 * weight
        v.y += clamp(p.headOffsetY.value, -20, 20) * (0.0007*(1-scruff)+0.00035*scruff) * headWeight
        v.y += (lie * 0.032 - scruff * 0.04) * weight
        v.y += (q.y-seat.y) * clamp(p.bodySquash.value-1, -0.045, 0.045) * weight
        // Ears and painted eyes move with the source state; no replacement eye design is introduced.
        let earWeight=(1-smooth(0.21,0.29,q.y))*smooth(0.08,0.17,abs(q.x-f.head.x))
        v.y += clamp(p.earFold.value,0,1)*0.009*earWeight
        v.x += p.earTwitch.value*0.0008*earWeight
        for e in [f.leftEye,f.rightEye] {
            let w=bump(q,CGPoint(x:e.midX,y:e.midY),0.07)
            v.x += p.eyeGaze.point.x*0.002*w
            v.y += p.eyeGaze.point.y*0.0015*w
        }

        do {
            let tailWeight = smooth(0.72, 0.85, q.x) * bump(q, f.tail, 0.22)
            v.x += sin(p.tailPhase)*0.012*tailWeight + clamp(p.tailFlick.point.x,-36,36)*0.0004*tailWeight
            v.y += (cos(p.tailPhase*1.3)*0.006+scruff*0.020)*tailWeight
        }
        if f.hasLegs {v.x += (0.47-v.x)*0.10*scruff*smooth(0.80,0.87,q.y)}
        return v
    }

    private static func drawImage(_ image: CGImage, in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: rect.width / CGFloat(image.width), y: -rect.height / CGFloat(image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.restoreGState()
    }

    private static func rigBitmap(_ image:CGImage,profile f:Profile)->CGImage {
        if let cached=rigBitmaps[f.character] {return cached}
        let w=image.width,h=image.height
        guard let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {return image}
        c.translateBy(x:0,y:CGFloat(h));c.scaleBy(x:1,y:-1)
        if let plate=bodyImage(f.character) {
            drawImage(plate,in:c,rect:CGRect(x:0,y:0,width:w,height:h))
            // The approved face stays pixel-for-pixel from the original; only the previously
            // occluded armless torso comes from the body backplate.
            c.saveGState();c.clip(to:CGRect(x:0,y:0,width:CGFloat(w),height:(f.hasLegs ? 0.60 : 0.36)*CGFloat(h)))
            drawImage(image,in:c,rect:CGRect(x:0,y:0,width:w,height:h));c.restoreGState()
            let result=c.makeImage() ?? image
            rigBitmaps[f.character]=result
            return result
        }
        drawImage(image,in:c,rect:CGRect(x:0,y:0,width:w,height:h))
        // Hardware is not part of the character texture. Otherwise pickup can reveal
        // a second, deformed keyboard even when the destination has a fixed hardware layer.
        c.clear(CGRect(x:0,y:(f.keyboard.minY-0.020)*CGFloat(h),width:CGFloat(w),height:CGFloat(h)))
        if f.hasLegs {
            c.saveGState();c.clip(to:CGRect(x:0.23*CGFloat(w),y:0.88*CGFloat(h),width:0.46*CGFloat(w),height:0.10*CGFloat(h)))
            drawImage(image,in:c,rect:CGRect(x:0,y:0,width:w,height:h));c.restoreGState()
        }
        let result=c.makeImage() ?? image
        rigBitmaps[f.character]=result
        return result
    }

    private static func triangle(_ s: [CGPoint], _ d: [CGPoint], image: CGImage, in ctx: CGContext) {
        let ux=s[1].x-s[0].x, uy=s[1].y-s[0].y, vx=s[2].x-s[0].x, vy=s[2].y-s[0].y
        let det=ux*vy-uy*vx
        guard abs(det)>0.0000001 else { return }
        let dx=d[1].x-d[0].x, dy=d[1].y-d[0].y, ex=d[2].x-d[0].x, ey=d[2].y-d[0].y
        let a=(dx*vy-ex*uy)/det, c=(ex*ux-dx*vx)/det
        let b=(dy*vy-ey*uy)/det, dd=(ey*ux-dy*vx)/det
        ctx.saveGState()
        ctx.beginPath(); ctx.move(to:d[0]); ctx.addLine(to:d[1]); ctx.addLine(to:d[2]); ctx.closePath(); ctx.clip()
        ctx.concatenate(CGAffineTransform(a:a,b:b,c:c,d:dd,tx:d[0].x-a*s[0].x-c*s[0].y,ty:d[0].y-b*s[0].x-dd*s[0].y))
        drawImage(image,in:ctx,rect:CGRect(x:0,y:0,width:1,height:1))
        ctx.restoreGState()
    }

    private static func crop(_ image: CGImage, rect: CGRect) -> CGImage? {
        image.cropping(to: CGRect(x:rect.minX*CGFloat(image.width), y:rect.minY*CGFloat(image.height),
                                 width:rect.width*CGFloat(image.width), height:rect.height*CGFloat(image.height)).integral)
    }

    private static func patch(_ rect: CGRect, sourceRect: CGRect, image: CGImage, profile f: Profile, in ctx: CGContext) {
        let key="\(f.character.rawValue)-\(sourceRect)"
        if patches[key] == nil {
            // Interpolate the surrounding skin, rather than copying a uniform yellow tile.
            // A feathered alpha edge keeps the original 3D shading / pencil grain continuous.
            var samples:[(CGFloat,CGFloat,[CGFloat])]=[]
            for i in 0..<32 {
                let a=CGFloat(i) * CGFloat.pi / 16, x=sourceRect.midX+cos(a)*sourceRect.width*0.53,
                    y=sourceRect.midY+sin(a)*sourceRect.height*0.53
                guard let pixel=crop(image,rect:CGRect(x:x-0.001,y:y-0.001,width:0.002,height:0.002)) else {continue}
                var rgba=[UInt8](repeating:0,count:4)
                rgba.withUnsafeMutableBytes { raw in
                    if let c=CGContext(data:raw.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,
                        space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) {
                        c.draw(pixel,in:CGRect(x:0,y:0,width:1,height:1))
                    }
                }
                // Reject iris, mouth and whisker strokes that intersect the sampling ring.
                if rgba[0] < 180 || rgba[1] < 130 {continue}
                if f.hasLegs && rgba[2] < 180 {continue}
                samples.append((cos(a),sin(a),rgba.prefix(3).map {CGFloat($0)}))
            }
            let size=128
            var bytes=[UInt8](repeating:0,count:size*size*4)
            for y in 0..<size {for x in 0..<size {
                let nx=(CGFloat(x)+0.5)/CGFloat(size)*2-1,ny=(CGFloat(y)+0.5)/CGFloat(size)*2-1
                let r=hypot(nx,ny),alpha=1-smooth(0.88,1,r)
                var total:CGFloat=0, colors=[CGFloat](repeating:0,count:3)
                for s in samples {
                    let weight=1/pow(max(0.03,hypot(nx-s.0,ny-s.1)),3)
                    total+=weight
                    for k in 0..<3 {colors[k]+=s.2[k]*weight}
                }
                let offset=(y*size+x)*4
                for k in 0..<3 {bytes[offset+k]=UInt8(clamp(colors[k]/max(1,total)*alpha,0,255))}
                bytes[offset+3]=UInt8(alpha*255)
            }}
            let data=Data(bytes) as CFData
            if let provider=CGDataProvider(data:data) {
                patches[key]=CGImage(width:size,height:size,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:size*4,
                    space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)
            }
        }
        if let sample=patches[key] {drawImage(sample,in:ctx,rect:rect)}
    }

    private static func eyes(image: CGImage, profile f: Profile, physics p: CatPhysics, in ctx: CGContext) {
        let closure=clamp(p.effectiveEyeClosure,0,1)
        let dizzy=clamp(p.dizzyIntensity.value,0,1)
        guard closure>0.015 || dizzy>0.35 else { return }
        for eye in [f.leftEye,f.rightEye] {
            let center=deform(CGPoint(x:eye.midX,y:eye.midY),physics:p,profile:f)
            let r=CGRect(x:center.x-eye.width/2,y:center.y-eye.height/2,width:eye.width,height:eye.height)
            patch(r.insetBy(dx:-0.016,dy:-0.014),sourceRect:eye.insetBy(dx:-0.016,dy:-0.014),image:image,profile:f,in:ctx)
            if dizzy>0.35 {
                ctx.setStrokeColor(f.ink); ctx.setLineWidth(0.003); ctx.beginPath()
                for i in 0...64 {
                    let t=CGFloat(i)/64, angle=t*CGFloat.pi*5+p.dizzyPhase
                    let pt=CGPoint(x:center.x+cos(angle)*eye.width*0.4*t,y:center.y+sin(angle)*eye.height*0.4*t)
                    if i==0 {ctx.move(to:pt)} else {ctx.addLine(to:pt)}
                }
                ctx.strokePath()
            } else if closure>0.90 {
                ctx.setStrokeColor(f.ink);ctx.setLineWidth(0.0025);ctx.setLineCap(.round)
                ctx.move(to:CGPoint(x:r.minX+0.01,y:center.y))
                ctx.addQuadCurve(to:CGPoint(x:r.maxX-0.01,y:center.y),control:CGPoint(x:center.x,y:center.y+0.014))
                ctx.strokePath()
            } else if let iris=crop(image,rect:eye) {
                let h=eye.height*max(0.04,1-closure)
                drawImage(iris,in:ctx,rect:CGRect(x:r.minX,y:center.y-h/2,width:r.width,height:h))
            }
        }
    }

    private static func mouth(image: CGImage, profile f: Profile, physics p: CatPhysics, in ctx: CGContext) {
        let amount=clamp(p.yawnAmount,0,1)
        guard amount>0.02 else {return}
        let c=deform(CGPoint(x:f.mouth.midX,y:f.mouth.midY),physics:p,profile:f)
        let cover=CGRect(x:c.x-f.mouth.width/2-0.01,y:c.y-f.mouth.height/2-0.01,
                         width:f.mouth.width+0.02,height:f.mouth.height+0.02)
        patch(cover,sourceRect:f.mouth.insetBy(dx:-0.01,dy:-0.01),image:image,profile:f,in:ctx)
        let r=CGRect(x:c.x-0.026,y:c.y-0.004,width:0.052,height:0.058*amount)
        ctx.setFillColor(CGColor(red:0.62,green:0.26,blue:0.24,alpha:1));ctx.fillEllipse(in:r)
        ctx.setStrokeColor(f.ink);ctx.setLineWidth(0.002);ctx.strokeEllipse(in:r)
        if amount>0.25 {
            ctx.saveGState();ctx.addEllipse(in:r);ctx.clip()
            ctx.setFillColor(CGColor(red:0.93,green:0.58,blue:0.61,alpha:1))
            ctx.fillEllipse(in:CGRect(x:r.minX+0.006,y:r.midY,width:r.width-0.012,height:r.height*0.75))
            ctx.restoreGState()
        }
    }

    /// Same key layout and normalized key centers as the native input physics (68 keys).
    static func keyPoint(_ key: PhysicalKey, character: ArtworkCharacter) -> CGPoint {
        let f=profile(character)
        guard let cap=(ArtworkKeyboardLayout.lookup[key] ?? ArtworkKeyboardLayout.lookup[key.visualKey]) else { return CGPoint(x:f.keyboard.midX,y:f.keyboard.midY) }
        let p=cap.normalizedCenter
        return keyboardPoint(1-p.x,1-p.y,profile:f)
    }

    private static func keyboardPoint(_ x:CGFloat,_ y:CGFloat,profile f:Profile)->CGPoint {
        let left:CGFloat=f.hasLegs ? 0.190-0.030*y : 0.205-0.024*y
        let right:CGFloat=f.hasLegs ? 0.768+0.039*y : 0.865+0.038*y
        return CGPoint(x:left+(right-left)*x,y:f.keyboard.minY+f.keyboard.height*y)
    }

    private static func keyboard(image:CGImage,profile f:Profile,in ctx:CGContext) {
        // Opaque full case, including the near apron: the torso cannot draw through the bezel.
        let bezel=[keyboardPoint(-0.016,-0.14,profile:f),keyboardPoint(1.016,-0.14,profile:f),
                   keyboardPoint(1.016,1.20,profile:f),keyboardPoint(-0.016,1.20,profile:f)]
        ctx.setFillColor(f.hasLegs ? CGColor(red:0.97,green:0.74,blue:0.75,alpha:1) : CGColor(red:0.40,green:0.53,blue:0.25,alpha:1))
        ctx.move(to:bezel[0]);for v in bezel.dropFirst(){ctx.addLine(to:v)};ctx.closePath();ctx.fillPath()
        let corners=[keyboardPoint(0,0,profile:f),keyboardPoint(1,0,profile:f),
                     keyboardPoint(1,1,profile:f),keyboardPoint(0,1,profile:f)]
        ctx.beginPath();ctx.move(to:corners[0]);for c in corners.dropFirst(){ctx.addLine(to:c)};ctx.closePath()
        let deck=f.hasLegs ? CGColor(red:0.78,green:0.48,blue:0.51,alpha:1) : CGColor(red:0.28,green:0.38,blue:0.20,alpha:1)
        ctx.setFillColor(deck);ctx.fillPath()
        for cap in ArtworkKeyboardLayout.keycaps {
            let sx=1-cap.xUnits-cap.widthUnits, sy=1-CGFloat(cap.row+1)/5
            let gap:CGFloat=0.0026
            let x0=sx+gap,x1=sx+cap.widthUnits-gap,y0=sy+0.010,y1=sy+0.190
            let q=[keyboardPoint(x0,y0,profile:f),keyboardPoint(x1,y0,profile:f),
                   keyboardPoint(x1,y1,profile:f),keyboardPoint(x0,y1,profile:f)]
            let modifier=cap.widthUnits>1.01/16 || cap.isAmberAccent || cap.key == .pageDown
            let keyColor:CGColor
            if f.hasLegs {
                keyColor=modifier ? CGColor(red:0.97,green:0.72,blue:0.73,alpha:1)
                    : CGColor(red:1,green:0.96,blue:0.93,alpha:1)
            } else {
                keyColor=cap.isAmberAccent ? CGColor(red:0.96,green:0.80,blue:0.28,alpha:1)
                    : CGColor(red:0.69,green:0.79,blue:0.44,alpha:1)
            }
            // Four quadratic corner arcs, with the key widths and row staggering from KeyMap.swift.
            let path=CGMutablePath(), radius:CGFloat=0.10
            for i in 0..<4 {
                let a=q[(i+3)%4],b=q[i],c=q[(i+1)%4]
                let before=CGPoint(x:b.x+(a.x-b.x)*radius,y:b.y+(a.y-b.y)*radius)
                let after=CGPoint(x:b.x+(c.x-b.x)*radius,y:b.y+(c.y-b.y)*radius)
                if i==0 {path.move(to:before)} else {path.addLine(to:before)}
                path.addQuadCurve(to:after,control:b)
            }
            path.closeSubpath()
            ctx.setFillColor(keyColor);ctx.addPath(path);ctx.fillPath()
            if f.hasLegs,let grain=crop(image,rect:f.faceSample) {
                ctx.saveGState();ctx.addPath(path);ctx.clip();ctx.setAlpha(modifier ? 0.12 : 0.45)
                let r=CGRect(x:q[0].x,y:q[0].y,width:q[1].x-q[0].x,height:q[3].y-q[0].y)
                drawImage(grain,in:ctx,rect:r);ctx.restoreGState()
            } else {
                ctx.saveGState();ctx.addPath(path);ctx.clip()
                let colors=[CGColor(gray:1,alpha:0.24),CGColor(gray:0,alpha:0.12)] as CFArray
                if let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1]) {
                    ctx.drawLinearGradient(g,start:q[0],end:q[3],options:[])
                };ctx.restoreGState()
            }
            ctx.setStrokeColor(deck);ctx.setLineWidth(f.hasLegs ? 0.0016 : 0.0010)
            ctx.addPath(path);ctx.strokePath()
        }
    }

    private static func palms(image:CGImage,profile f:Profile,physics p:CatPhysics,in ctx:CGContext) {
        guard f.hasLegs else {return}
        for center in [f.leftWrist,f.rightWrist] {
            if armMoves(center == f.leftWrist,physics:p) {continue}
            let r=CGRect(x:center.x-0.051,y:center.y-0.026,width:0.102,height:0.052)
            guard let paw=crop(image,rect:r) else {continue}
            let to=deform(center,physics:p,profile:f)
            let dest=CGRect(x:to.x-r.width/2,y:to.y-r.height/2,width:r.width,height:r.height)
            ctx.saveGState();ctx.addEllipse(in:dest);ctx.clip();drawImage(paw,in:ctx,rect:dest);ctx.restoreGState()
        }
    }

    private static func armMoves(_ left:Bool,physics p:CatPhysics)->Bool {
        if p.scruffDrag.value>0.15 {return true}
        guard p.dizzyIntensity.value<0.35 && p.lieIntensity.value<0.45 else {return false}
        let point=left ? p.leftPaw.point : p.rightPaw.point
        let rest=left ? CatPhysics.leftPawRest : CatPhysics.rightPawRest
        return hypot(point.x-rest.x,point.y-rest.y)>6
    }

    static func wrist(_ left:Bool,physics p:CatPhysics,character:ArtworkCharacter)->CGPoint {
        let f=profile(character)
        let rest=deform(left ? f.leftWrist : f.rightWrist,physics:p,profile:f)
        let native=left ? p.leftPaw : p.rightPaw
        let nr=left ? CatPhysics.leftPawRest : CatPhysics.rightPawRest
        if p.scruffDrag.value>0.15 {
            let down=CGPoint(x:f.hasLegs ? (left ? 0.415 : 0.545) : (left ? 0.32 : 0.65),y:f.hasLegs ? 0.795 : 0.695)
            let hanging=deform(down,physics:p,profile:f)
            let tucked=rest
            let t=smooth(0.15,0.8,p.scruffDrag.value)
            return CGPoint(x:tucked.x+(hanging.x-tucked.x)*t,y:tucked.y+(hanging.y-tucked.y)*t)
        }
        let target:CGPoint
        if left && p.leftPawOnMouse {
            target=CGPoint(x:f.mouse.x+p.mouseOffset.point.x/360,y:f.mouse.y+p.mouseOffset.point.y/320-0.008)
        } else if (left ? p.leftPawTyping : p.rightPawTyping),
            let cap=ArtworkKeyboardLayout.keycaps.min(by:{
                let a=KeyboardLayout.canvasPoint(for:$0.key),b=KeyboardLayout.canvasPoint(for:$1.key)
                return hypot(a.x-native.target.x,a.y-native.target.y)<hypot(b.x-native.target.x,b.y-native.target.y)
            }) {
            target=keyPoint(cap.key,character:character)
        } else {return rest}
        let travel=max(1,hypot(native.target.x-nr.x,native.target.y-nr.y))
        let progress=clamp(hypot(native.point.x-nr.x,native.point.y-nr.y)/travel,0,1.06)
        return CGPoint(x:rest.x+(target.x-rest.x)*progress,y:rest.y+(target.y-rest.y)*progress)
    }

    private static func eraseArms(image:CGImage,profile f:Profile,physics p:CatPhysics,in ctx:CGContext) {
        if bodyImage(f.character) != nil {return}
        for left in [true,false] where armMoves(left,physics:p) {
            let rect:CGRect
            if f.hasLegs {rect=CGRect(x:left ? 0.250 : 0.500,y:0.590,width:0.200,height:0.165)}
            else {rect=CGRect(x:left ? 0.120 : 0.650,y:0.440,width:0.220,height:0.220)}
            patch(rect,sourceRect:rect,image:image,profile:f,in:ctx)
        }
    }

    private static func idleArms(image:CGImage,profile f:Profile,physics p:CatPhysics,in ctx:CGContext) {
        guard bodyImage(f.character) != nil else {return}
        for left in [true,false] where !armMoves(left,physics:p) {
            let center=left ? f.leftWrist : f.rightWrist
            let to=deform(center,physics:p,profile:f)
            ctx.saveGState();ctx.translateBy(x:to.x-center.x,y:to.y-center.y)
            if f.hasLegs {
                let points:[CGPoint]=left ? [
                    CGPoint(x:0.31,y:0.599),CGPoint(x:0.355,y:0.605),CGPoint(x:0.395,y:0.65),
                    CGPoint(x:0.417,y:0.705),CGPoint(x:0.402,y:0.735),CGPoint(x:0.321,y:0.735),
                    CGPoint(x:0.285,y:0.676),CGPoint(x:0.273,y:0.625)
                ] : [
                    CGPoint(x:0.630,y:0.599),CGPoint(x:0.584,y:0.605),CGPoint(x:0.545,y:0.65),
                    CGPoint(x:0.523,y:0.705),CGPoint(x:0.538,y:0.735),CGPoint(x:0.619,y:0.735),
                    CGPoint(x:0.655,y:0.676),CGPoint(x:0.667,y:0.625)
                ]
                ctx.move(to:points[0]);for v in points.dropFirst(){ctx.addLine(to:v)};ctx.closePath();ctx.clip()
            } else {
                ctx.addEllipse(in:CGRect(x:left ? 0.13 : 0.68,y:0.46,width:0.18,height:0.17));ctx.clip()
            }
            drawImage(image,in:ctx,rect:CGRect(x:0,y:0,width:1,height:1));ctx.restoreGState()
        }
    }

    private static func arms(image:CGImage,profile f:Profile,physics p:CatPhysics,in ctx:CGContext) {
        for left in [true,false] where armMoves(left,physics:p) {
            let shoulder=deform(CGPoint(x:f.hasLegs ? (left ? 0.315 : 0.628) : (left ? 0.195 : 0.785),
                                      y:f.hasLegs ? 0.612 : 0.505),physics:p,profile:f)
            let end=wrist(left,physics:p,character:f.character)
            let mid=CGPoint(x:(shoulder.x+end.x)/2+(left ? -0.025 : 0.025),y:(shoulder.y+end.y)/2-0.015)
            // Same sampled quadratic ribbon construction as CatRenderer.drawLimb (14 steps),
            // with a broad shoulder and tapered wrist; not a stretched rectangular texture.
            var edgeA:[CGPoint]=[],edgeB:[CGPoint]=[]
            for i in 0...14 {
                let t=CGFloat(i)/14,u=1-t
                let c=CGPoint(x:u*u*shoulder.x+2*u*t*mid.x+t*t*end.x,y:u*u*shoulder.y+2*u*t*mid.y+t*t*end.y)
                let dx=2*u*(mid.x-shoulder.x)+2*t*(end.x-mid.x),dy=2*u*(mid.y-shoulder.y)+2*t*(end.y-mid.y)
                let length=max(0.0001,hypot(dx,dy)),half=(0.085+(0.052-0.085)*t)/2
                edgeA.append(CGPoint(x:c.x-dy/length*half,y:c.y+dx/length*half))
                edgeB.append(CGPoint(x:c.x+dy/length*half,y:c.y-dx/length*half))
            }
            let inner=CGMutablePath();inner.move(to:edgeA[0])
            for v in edgeA.dropFirst(){inner.addLine(to:v)}
            inner.addQuadCurve(to:edgeB.last!,control:CGPoint(x:end.x+(end.x-mid.x)*0.10,y:end.y+(end.y-mid.y)*0.10))
            for v in edgeB.reversed().dropFirst(){inner.addLine(to:v)}
            inner.addQuadCurve(to:edgeA[0],control:CGPoint(x:shoulder.x+(shoulder.x-mid.x)*0.12,y:shoulder.y+(shoulder.y-mid.y)*0.12))
            inner.closeSubpath()
            ctx.setFillColor(f.hasLegs ? CGColor(red:1,green:0.95,blue:0.94,alpha:1) : CGColor(red:252/255,green:195/255,blue:89/255,alpha:1))
            ctx.addPath(inner);ctx.fillPath()
            ctx.saveGState();ctx.addPath(inner);ctx.clip()
            if f.hasLegs, let texture=crop(image,rect:f.faceSample) {
                drawImage(texture,in:ctx,rect:inner.boundingBoxOfPath)
            } else {
                // Use the body's actual golden material instead of a separate lemon-yellow fill.
                if let plate=bodyImage(f.character),let material=crop(plate,rect:CGRect(x:0.35,y:0.48,width:0.12,height:0.14)) {
                    drawImage(material,in:ctx,rect:inner.boundingBoxOfPath)
                }
                let dx=end.x-shoulder.x,dy=end.y-shoulder.y,length=max(0.001,hypot(dx,dy))
                let n=CGPoint(x:-dy/length*0.04,y:dx/length*0.04)
                if let shading=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[
                    CGColor(gray:0,alpha:0.10),CGColor(gray:0,alpha:0),CGColor(gray:1,alpha:0.07)
                ] as CFArray,locations:[0,0.5,1]) {
                    ctx.drawLinearGradient(shading,start:CGPoint(x:mid.x-n.x,y:mid.y-n.y),
                        end:CGPoint(x:mid.x+n.x,y:mid.y+n.y),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
                }
            };ctx.restoreGState()
            // Only the sides are outlined: no seam or cuff is drawn across the shoulder joint.
            ctx.setStrokeColor(f.ink);ctx.setLineWidth(f.hasLegs ? 0.0018 : 0.0008)
            ctx.move(to:edgeA[3]);for v in edgeA.dropFirst(4){ctx.addLine(to:v)};ctx.strokePath()
            ctx.move(to:edgeB[3]);for v in edgeB.dropFirst(4){ctx.addLine(to:v)};ctx.strokePath()
            if f.hasLegs {
                let center=left ? f.leftWrist : f.rightWrist
                let rect=CGRect(x:center.x-0.051,y:center.y-0.026,width:0.102,height:0.052)
                if let paw=crop(image,rect:rect) {
                    let dest=CGRect(x:end.x-rect.width/2,y:end.y-rect.height/2,width:rect.width,height:rect.height)
                    ctx.saveGState();ctx.addEllipse(in:dest);ctx.clip();drawImage(paw,in:ctx,rect:dest);ctx.restoreGState()
                }
            } else {
                let paw=CGRect(x:end.x-0.032,y:end.y-0.022,width:0.064,height:0.044)
                ctx.saveGState();ctx.addEllipse(in:paw);ctx.clip()
                ctx.setFillColor(CGColor(red:252/255,green:195/255,blue:89/255,alpha:1));ctx.fill(paw)
                if let plate=bodyImage(f.character),let material=crop(plate,rect:CGRect(x:0.35,y:0.48,width:0.12,height:0.14)) {
                    drawImage(material,in:ctx,rect:paw)
                };ctx.restoreGState()
            }
        }
    }

    @discardableResult
    static func draw(in ctx: CGContext, physics p: CatPhysics, character: ArtworkCharacter) -> Bool {
        guard let image=image(character) else { return false }
        let f=profile(character), rect=stageRect(image)
        ctx.saveGState();ctx.translateBy(x:rect.minX,y:rect.minY);ctx.scaleBy(x:rect.width,y:rect.height)
        ctx.interpolationQuality = .high
        // Draw hardware from the immutable reference first. It must never follow the body rig.
        let completeBody=bodyImage(character) != nil
        let equipmentAlpha=clamp(1-p.scruffDrag.value*2.6,0,1)
        let equipmentY=f.keyboard.minY-0.004
        if completeBody {
            ctx.saveGState();ctx.addRect(CGRect(x:0,y:equipmentY-0.02,width:1,height:1-equipmentY+0.02))
            if f.hasLegs {ctx.addRect(CGRect(x:0.23,y:0.88,width:0.46,height:0.12))}
            ctx.clip(using:.evenOdd);ctx.setAlpha(equipmentAlpha);drawImage(image,in:ctx,rect:CGRect(x:0,y:0,width:1,height:1));ctx.restoreGState()
        } else {drawImage(image,in:ctx,rect:CGRect(x:0,y:0,width:1,height:1))}
        ctx.saveGState()
        if !completeBody {
            ctx.addRect(CGRect(x:0,y:0,width:1,height:equipmentY))
            if f.hasLegs {ctx.addRect(CGRect(x:0.23,y:0.88,width:0.46,height:0.10))}
            ctx.clip()
        }
        if let animated=warpedImage(image,physics:p,profile:f) {
            // Clear only this compositing layer so the original rest pose does not remain underneath.
            if !completeBody {ctx.clear(CGRect(x:0,y:0,width:1,height:1))}
            drawImage(animated,in:ctx,rect:warpRects[character] ?? CGRect(x:0,y:0,width:1,height:1))
        } else {
          lastBackend="triangle-fallback"
          // Fallback for machines without Core Image kernel support.
          ctx.setShouldAntialias(false)
          let columns=8, rows=14
          for j in 0..<rows {for i in 0..<columns {
            let a=CGPoint(x:CGFloat(i)/CGFloat(columns),y:CGFloat(j)/CGFloat(rows))
            let b=CGPoint(x:CGFloat(i+1)/CGFloat(columns),y:a.y)
            let c=CGPoint(x:b.x,y:CGFloat(j+1)/CGFloat(rows)), d=CGPoint(x:a.x,y:c.y)
            let dd=[a,b,c,d].map {deform($0,physics:p,profile:f)}
            let texture=rigBitmap(image,profile:f)
            triangle([a,b,c],[dd[0],dd[1],dd[2]],image:texture,in:ctx)
            triangle([a,c,d],[dd[0],dd[2],dd[3]],image:texture,in:ctx)
          }}
        }
        ctx.restoreGState()
        ctx.setShouldAntialias(true)
        eyes(image:image,profile:f,physics:p,in:ctx)
        mouth(image:image,profile:f,physics:p,in:ctx)
        eraseArms(image:image,profile:f,physics:p,in:ctx)
        idleArms(image:image,profile:f,physics:p,in:ctx)
        if equipmentAlpha>0.01 {
            ctx.saveGState();ctx.setAlpha(equipmentAlpha);ctx.beginTransparencyLayer(auxiliaryInfo:nil)
            keyboard(image:image,profile:f,in:ctx)
            ctx.endTransparencyLayer();ctx.restoreGState()
            if f.hasLegs {
                ctx.saveGState();ctx.setAlpha(equipmentAlpha)
                for foot in [CGRect(x:0.250,y:0.875,width:0.155,height:0.075),CGRect(x:0.520,y:0.875,width:0.155,height:0.075)] {
                    ctx.saveGState();ctx.addEllipse(in:foot);ctx.clip();drawImage(image,in:ctx,rect:CGRect(x:0,y:0,width:1,height:1));ctx.restoreGState()
                };ctx.restoreGState()
            }
        }
        palms(image:image,profile:f,physics:p,in:ctx)
        arms(image:image,profile:f,physics:p,in:ctx)
        for (key,intensity) in p.keyGlow where intensity>0.02 && equipmentAlpha>0.01 {
            let pt=keyPoint(key,character:character)
            ctx.setFillColor(CGColor(red:1,green:0.88,blue:0.48,alpha:clamp(intensity,0,1)*0.35*equipmentAlpha))
            ctx.fillEllipse(in:CGRect(x:pt.x-0.010,y:pt.y-0.006,width:0.020,height:0.012))
        }
        let press=max(p.mousePressLeft.value,p.mousePressRight.value)
        if press>0.02 && equipmentAlpha>0.01 {
            ctx.setFillColor(CGColor(red:1,green:0.77,blue:0.36,alpha:clamp(press,0,1)*0.4*equipmentAlpha))
            ctx.fillEllipse(in:CGRect(x:f.mouse.x-0.018,y:f.mouse.y+0.025,width:0.036,height:0.025))
        }
        ctx.restoreGState()
        return true
    }

    static func hitTest(_ p: CGPoint, character: ArtworkCharacter) -> CatHitZone {
        guard let image=image(character) else {return .none}
        let r=stageRect(image), f=profile(character)
        let q=CGPoint(x:(p.x-r.minX)/r.width,y:(p.y-r.minY)/r.height)
        guard q.x>=0 && q.x<=1 && q.y>=0 && q.y<=1 else {return .none}
        let rx:CGFloat=f.hasLegs ? 0.32 : 0.24, ry:CGFloat=f.hasLegs ? 0.20 : 0.17
        let dx=(q.x-f.head.x)/rx,dy=(q.y-f.head.y)/ry
        if dx*dx+dy*dy<1 {return .head}
        if f.keyboard.insetBy(dx:-0.12,dy:-0.01).contains(q) ||
           (q.x>0.18 && q.x<0.85 && q.y>0.50 && q.y<f.keyboard.minY) {return .body}
        return .none
    }

    static func nativeTailProbe(_ point: CGPoint, character: ArtworkCharacter) -> CGPoint? {
        guard let image=image(character) else {return nil}
        let r=stageRect(image), f=profile(character)
        let q=CGPoint(x:(point.x-r.minX)/r.width,y:(point.y-r.minY)/r.height)
        if hypot(q.x-f.tail.x,q.y-f.tail.y)<0.16 {return CGPoint(x:275,y:196)}
        return nil
    }
}

/// ANSI 68-key layout used only by these artwork characters.
enum ArtworkKeyboardLayout {
    static let keycaps: [VisualKeycap] = {
        let rows: [[(PhysicalKey, CGFloat, Bool)]] = [
            // Row 0: 16u, 15 keys (Esc lands at bottom-right when facing cat).
            [
                (.escape, 1.0, true), (.k1, 1.0, false), (.k2, 1.0, false), (.k3, 1.0, false),
                (.k4, 1.0, false), (.k5, 1.0, false), (.k6, 1.0, false), (.k7, 1.0, false),
                (.k8, 1.0, false), (.k9, 1.0, false), (.k0, 1.0, false), (.minus, 1.0, false),
                (.equal, 1.0, false), (.backspace, 2.0, false), (.forwardDelete, 1.0, false)
            ],
            // Row 1: 16u, 15 keys.
            [
                (.tab, 1.5, false), (.q, 1.0, false), (.w, 1.0, false), (.e, 1.0, false),
                (.r, 1.0, false), (.t, 1.0, false), (.y, 1.0, false), (.u, 1.0, false),
                (.i, 1.0, false), (.o, 1.0, false), (.p, 1.0, false), (.leftBracket, 1.0, false),
                (.rightBracket, 1.0, false), (.backslash, 1.5, false), (.home, 1.0, false)
            ],
            // Row 2: 16u, 14 keys (Enter lands at viewer-left).
            [
                (.capsLock, 1.75, false), (.a, 1.0, false), (.s, 1.0, false), (.d, 1.0, false),
                (.f, 1.0, false), (.g, 1.0, false), (.h, 1.0, false), (.j, 1.0, false),
                (.k, 1.0, false), (.l, 1.0, false), (.semicolon, 1.0, false), (.quote, 1.0, false),
                (.enter, 2.25, true), (.pageUp, 1.0, false)
            ],
            // Row 3: 16u, 14 keys.
            [
                (.leftShift, 2.25, false), (.z, 1.0, false), (.x, 1.0, false), (.c, 1.0, false),
                (.v, 1.0, false), (.b, 1.0, false), (.n, 1.0, false), (.m, 1.0, false),
                (.comma, 1.0, false), (.period, 1.0, false), (.slash, 1.0, false),
                (.rightShift, 1.75, false), (.arrowUp, 1.0, false), (.pageDown, 1.0, false)
            ],
            // Row 4: 16u, 10 keys (spacebar nearest the cat).
            [
                (.leftControl, 1.25, false), (.leftOption, 1.25, false), (.leftCommand, 1.25, false),
                (.space, 6.25, false),
                (.rightCommand, 1.0, false), (.rightOption, 1.0, false), (.fn, 1.0, false),
                (.arrowLeft, 1.0, false), (.arrowDown, 1.0, false), (.arrowRight, 1.0, false)
            ]
        ]

        var result: [VisualKeycap] = []
        let totalUnits: CGFloat = 16.0
        for (rowIdx, row) in rows.enumerated() {
            var cursor: CGFloat = 0
            for (key, width, isAmber) in row {
                result.append(VisualKeycap(
                    key: key,
                    row: rowIdx,
                    xUnits: cursor / totalUnits,
                    widthUnits: width / totalUnits,
                    isAmberAccent: isAmber
                ))
                cursor += width
            }
        }
        return result
    }()

    static let lookup = Dictionary(uniqueKeysWithValues: keycaps.map { ($0.key, $0) })
}
