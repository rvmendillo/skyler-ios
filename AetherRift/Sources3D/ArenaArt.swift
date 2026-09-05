import SceneKit
import UIKit

// Original runtime-generated meshes. No downloaded characters or game artwork.
extension ArenaRenderer {
    /// An elliptical surface of revolution with explicit normals and UVs.
    func sculpt(_ profile:[(Float,Float,Float)], sides:Int=24)->SCNGeometry {
        var v:[SCNVector3]=[];var normals:[SCNVector3]=[];var uv:[CGPoint]=[];var indices:[Int32]=[]
        for (row,p) in profile.enumerated() {
            let before=profile[max(0,row-1)],after=profile[min(profile.count-1,row+1)]
            let rise=max(0.001,after.0-before.0)
            for col in 0...sides {
                let a=Float(col)*2 * .pi/Float(sides),c=cos(a),s=sin(a)
                v.append(SCNVector3(c*p.1,p.0,s*p.2))
                let nx=c/max(0.01,p.1),nz=s/max(0.01,p.2)
                let ny = -((after.1-before.1)*c*c/max(0.01,p.1)+(after.2-before.2)*s*s/max(0.01,p.2))/rise
                let length=sqrt(nx*nx+ny*ny+nz*nz)
                normals.append(SCNVector3(nx/length,ny/length,nz/length));uv.append(CGPoint(x:Double(col)/Double(sides),y:Double(row)/Double(profile.count-1)))
                if row<profile.count-1 && col<sides {let a=Int32(row*(sides+1)+col),b=a+Int32(sides+1);indices += [a,b,a+1,a+1,b,b+1]}
            }
        }
        return SCNGeometry(sources:[SCNGeometrySource(vertices:v),SCNGeometrySource(normals:normals),SCNGeometrySource(textureCoordinates:uv)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
    }
    func jewel(_ radius:CGFloat,color:UIColor,at p:SCNVector3,in parent:SCNNode)->SCNNode {
        let r=Float(radius)
        return mesh(sculpt([(-r,0.002,0.002),(0,r*0.65,r*0.65),(r,0.002,0.002)],sides:6),color,p,parent,metal:0.5,glow:true)
    }
    func clothPanel(width:Float,length:Float,color:UIColor,at p:SCNVector3,in parent:SCNNode)->SCNNode {
        var vertices:[SCNVector3]=[];var uv:[CGPoint]=[];var idx:[Int32]=[]
        for y in 0...10 {for x in 0...8 {
            let t=Float(y)/10,s=Float(x)/8
            vertices.append(SCNVector3((s-0.5)*width*(1+t*0.36),-t*length,-0.10-t*0.38+cos(s*6 * .pi)*t*0.035))
            uv.append(CGPoint(x:Double(s),y:Double(t)))
            if y<10 && x<8{let a=Int32(y*9+x);idx += [a,a+1,a+9,a+1,a+10,a+9]}
        }}
        let geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:vertices.map{_ in SCNVector3(0,0,-1)}),SCNGeometrySource(textureCoordinates:uv)],elements:[SCNGeometryElement(indices:idx,primitiveType:.triangles)])
        let n=mesh(geometry,color,p,parent);geometry.firstMaterial?.isDoubleSided=true
        geometry.shaderModifiers=[.geometry:"float hem = _geometry.texcoords[0].y; _geometry.position.z += sin(u_time * 2.7 + _geometry.position.x * 5.0 + hem * 4.0) * hem * 0.065;"]
        return n
    }
    func sculptHero(_ def:HeroDef,team:Int,preview:Bool)->SCNNode {
        let root=SCNNode(),body=SCNNode();body.name="body";root.addChildNode(body)
        let heavy=def.role == .tank, arcane=def.role == .mage || def.role == .support, agile=def.role == .assassin
        let feminine=[3,5,7,9,11].contains(def.id)
        let tint=UIColor(rgb:def.color),cloth=tint.darker(0.40),steel=UIColor(rgb:0x8FADB6),dark=UIColor(rgb:0x172936),leather=UIColor(rgb:0x493D38),trim=UIColor(rgb:0xC4A36A)
        let skin=UIColor(rgb:[UInt32(0xBA8868),0xD9AB8B,0xBB8D74,0xD6BDA6][def.id%4])
        let w:Float=heavy ? 0.53:feminine ? 0.34:0.40
        // Feet, articulated thighs, knee joints, and fitted greaves.
        for side:Float in [-1,1] {
            let leg=SCNNode();leg.name=side<0 ? "legL":"legR";leg.position=SCNVector3(side*w*0.49,1.44,0);body.addChildNode(leg)
            _=mesh(sculpt([(-0.68,0.115,0.125),(-0.43,0.16,0.17),(-0.1,heavy ? 0.22:0.18,0.19),(0,0.13,0.15)]),dark,SCNVector3Zero,leg)
            let shin=SCNNode();shin.name="shin";shin.position=SCNVector3(0,-0.67,0.025);leg.addChildNode(shin)
            _=mesh(sculpt([(-0.60,0.10,0.115),(-0.43,0.12,0.14),(-0.18,0.16,0.17),(0.05,0.13,0.14)]),heavy ? steel:leather,SCNVector3Zero,shin,metal:heavy ? 0.55:0.05)
            let plate=sphere(0.17,heavy ? trim:steel,SCNVector3(0,0.025,0.125),shin,scale:SCNVector3(0.76,1.1,0.36));plate.geometry?.firstMaterial?.metalness.contents=0.55
            _=sphere(0.18,dark,SCNVector3(0,-0.64,0.10),shin,scale:SCNVector3(0.78,0.57,1.6))
            _=box(0.21,0.035,0.39,trim,SCNVector3(0,-0.70,0.12),shin,bevel:0.012,metal:0.4)
        }
        _=mesh(sculpt([(1.31,w*0.78,0.22),(1.45,w*0.9,0.23),(1.67,w*0.71,0.20),(1.88,w*0.89,0.255),(2.12,w,0.25),(2.23,w*0.85,0.21),(2.32,0.13,0.12)]),cloth,SCNVector3Zero,body,metal:heavy ? 0.60:0.12)
        // Layered breastplate, edge inlay, waist sash, and asymmetric armor.
        let breast=mesh(sculpt([(-0.3,w*0.50,0.035),(-0.12,w*0.80,0.09),(0.13,w*0.92,0.10),(0.28,w*0.74,0.06)]),heavy ? steel:dark,SCNVector3(0,1.96,0.225),body,metal:0.55)
        breast.scale.z=0.8
        for side:Float in [-1,1] {
            let inset=box(0.028,0.50,0.025,trim,SCNVector3(side*w*0.57,1.94,0.303),body,bevel:0.008,metal:0.75);inset.eulerAngles.z = -side*0.20
        }
        _=mesh(sculpt([(1.43,w*0.91,0.245),(1.51,w*0.9,0.242),(1.54,w*0.87,0.238)]),leather,SCNVector3Zero,body)
        _=box(0.16,0.13,0.045,trim,SCNVector3(0,1.49,0.263),body,bevel:0.018,metal:0.8)
        _=jewel(0.09,color:tint,at:SCNVector3(0,2.19,0.275),in:body)
        if arcane {
            _=mesh(sculpt([(0.30,w*1.16,0.36),(0.41,w*1.13,0.34),(0.92,w*0.9,0.27),(1.43,w*0.81,0.23)],sides:28),cloth,SCNVector3Zero,body)
            let hem=mesh(SCNTorus(ringRadius:CGFloat(w*1.16),pipeRadius:0.016),trim,SCNVector3(0,0.34,0),body,metal:0.5);hem.scale.z=0.8
        }
        let cape=clothPanel(width:heavy ? 1.08:0.76,length:agile ? 1.1:1.8,color:cloth,at:SCNVector3(0,2.26,-0.13),in:body);cape.name="cape"
        if def.id==7 || def.id==8 {_=clothPanel(width:0.20,length:0.95,color:tint,at:SCNVector3(-0.21,1.49,0.12),in:body)}
        _=mesh(SCNCapsule(capRadius:0.09,height:0.27),skin,SCNVector3(0,2.40,0),body)
        let head=SCNNode();head.position=SCNVector3(0,2.66,0.015);body.addChildNode(head)
        _=mesh(sculpt([(-0.23,0.055,0.075),(-0.19,0.10,0.125),(-0.10,0.145,0.153),(0.01,0.16,0.157),(0.15,0.151,0.145),(0.23,0.09,0.09),(0.255,0.003,0.003)],sides:32),skin,SCNVector3Zero,head)
        let hair=UIColor(rgb:[UInt32(0xBCC4C6),0x4B2920,0x222232,0xCBC2AC][def.id%4])
        _=mesh(sculpt([(0.055,0.159,0.146),(0.15,0.168,0.155),(0.25,0.14,0.13),(0.30,0.06,0.07),(0.31,0.001,0.001)]),hair,SCNVector3(0,0,-0.018),head)
        for i in 0..<7 {
            let lock=mesh(SCNCone(topRadius:0.008,bottomRadius:0.060,height:feminine ? 0.37:0.18),hair,SCNVector3(Float(i-3)*0.043,0.09+Float(i%2)*0.025,-0.075),head)
            lock.eulerAngles=SCNVector3(feminine ? 2.85:2.05,Float(i)*0.35,Float(i-3)*0.20)
        }
        _=sphere(0.036,skin,SCNVector3(0,-0.022,0.157),head,scale:SCNVector3(0.50,1.05,0.92))
        _=box(0.055,0.010,0.014,UIColor(rgb:0x845954),SCNVector3(0,-0.114,0.136),head,bevel:0.004)
        for side:Float in [-1,1] {
            _=sphere(0.024,UIColor(rgb:0xDCDCD2),SCNVector3(side*0.068,0.025,0.137),head,scale:SCNVector3(1.28,0.45,0.36))
            _=sphere(0.012,UIColor(rgb:0x354D53),SCNVector3(side*0.068,0.025,0.147),head,scale:SCNVector3(0.66,0.86,0.45))
            let brow=box(0.065,0.015,0.012,hair,SCNVector3(side*0.068,0.065,0.143),head,bevel:0.004);brow.eulerAngles.z=side*0.08
            _=sphere(0.031,skin,SCNVector3(side*0.158,-0.005,0),head,scale:SCNVector3(0.45,1.35,0.75))
        }
        if heavy {
            for side:Float in [-1,1] {
                _=box(0.09,0.25,0.25,steel,SCNVector3(side*0.17,-0.04,-0.015),head,bevel:0.03,metal:0.65)
                let crest=mesh(SCNCone(topRadius:0.006,bottomRadius:0.07,height:0.35),trim,SCNVector3(side*0.12,0.36,-0.02),head,metal:0.6);crest.eulerAngles.z = -side*0.28
            }
            _=box(0.031,0.23,0.04,trim,SCNVector3(0,0.10,0.165),head,bevel:0.008,metal:0.7)
        } else if arcane {
            let circlet=mesh(SCNTorus(ringRadius:0.167,pipeRadius:0.017),trim,SCNVector3(0,0.14,0),head,metal:0.8);circlet.scale.z=0.92
            _=jewel(0.075,color:tint,at:SCNVector3(0,0.16,0.168),in:head)
        } else if agile {_=mesh(sculpt([(-0.20,0.08,0.11),(-0.12,0.15,0.158),(-0.07,0.155,0.162)]),dark,SCNVector3Zero,head)}
        for side:Float in [-1,1] {
            let arm=SCNNode();arm.name=side<0 ? "armL":"armR";arm.position=SCNVector3(side*(w+0.05),2.19,0);body.addChildNode(arm);arm.eulerAngles.z = side*0.06
            _=mesh(sculpt([(-0.53,0.088,0.105),(-0.3,0.12,0.13),(-0.06,0.15,0.16),(0.05,0.10,0.12)]),cloth,SCNVector3Zero,arm)
            let shoulder=sphere(heavy ? 0.255:0.18,heavy || side<0 ? steel:cloth,SCNVector3(side*0.02,-0.015,0),arm,scale:SCNVector3(1.15,0.78,1.0));shoulder.geometry?.firstMaterial?.metalness.contents=0.65
            _=mesh(sculpt([(-0.94,0.075,0.085),(-0.83,0.11,0.105),(-0.55,0.105,0.12),(-0.48,0.08,0.10)]),heavy ? steel:leather,SCNVector3Zero,arm,metal:0.35)
            _=sphere(0.087,skin,SCNVector3(0,-1.0,0.02),arm,scale:SCNVector3(0.72,1.1,0.8))
            if heavy {for i in 0..<2{let spike=mesh(SCNCone(topRadius:0,bottomRadius:0.06,height:0.22),trim,SCNVector3(side*(0.10+Float(i)*0.11),0.14,0),arm,metal:0.5);spike.eulerAngles.z = -side*0.35}}
        }
        let hand=body.childNode(withName:"armR",recursively:false)!,weapon=SCNNode();weapon.name="weapon";weapon.position=SCNVector3(0,-0.99,0.025);hand.addChildNode(weapon)
        if arcane {
            _=cylinder(0.028,2.17,leather,SCNVector3(0,0.40,0),weapon)
            for h:Float in [-0.5,0.05,1.35]{_=cylinder(0.041,0.13,trim,SCNVector3(0,h,0),weapon)}
            _=jewel(0.24,color:tint,at:SCNVector3(0,1.63,0),in:weapon)
            let halo=ring(0.26,color:trim,parent:weapon,height:1.60);halo.eulerAngles.x = .pi/2;halo.name="focus"
        } else if def.id==10 {
            _=box(0.12,0.14,0.92,dark,SCNVector3(0,0.06,0.30),weapon,bevel:0.025,metal:0.6)
            let barrel=cylinder(0.045,0.70,steel,SCNVector3(0,0.06,0.70),weapon);barrel.eulerAngles.x = .pi/2
            _=box(0.07,0.18,0.16,leather,SCNVector3(0,-0.04,0.05),weapon,bevel:0.02)
        } else if def.role == .marksman {
            for i in 0..<16 {let a=Float(i)*Float.pi/16-Float.pi/2,b=Float(i+1)*Float.pi/16-Float.pi/2
                let rod=cylinder(0.025,CGFloat(hypot(sin(b)-sin(a),cos(b)-cos(a)))*0.73,trim,SCNVector3(0,(sin(a)+sin(b))*0.365,(cos(a)+cos(b))*0.22),weapon);rod.eulerAngles.x = (a+b)/2
            }
            _=box(0.009,1.46,0.009,UIColor(rgb:0xC8DCE0),SCNVector3Zero,weapon,bevel:0)
            _=box(0.015,0.015,0.8,leather,SCNVector3(0,0,0.18),weapon,bevel:0)
        } else {
            _=cylinder(0.043,0.24,leather,SCNVector3Zero,weapon)
            let blade=mesh(sculpt([(0.12,0.11,0.035),(0.28,0.09,0.018),(agile ? 0.77:1.10,0.065,0.012),(agile ? 0.92:1.38,0.001,0.001)],sides:4),steel,SCNVector3Zero,weapon,metal:0.80)
            blade.eulerAngles.y = .pi/4
            _=box(0.34,0.055,0.075,trim,SCNVector3(0,0.13,0),weapon,bevel:0.016,metal:0.7)
            _=jewel(0.06,color:tint,at:SCNVector3(0,-0.18,0),in:weapon)
            if heavy {
                let arm=body.childNode(withName:"armL",recursively:false)!
                let shield=mesh(sculpt([(-0.50,0.035,0.015),(-0.32,0.27,0.09),(0.28,0.34,0.10),(0.43,0.23,0.06)],sides:6),cloth,SCNVector3(-0.10,-0.56,0.20),arm,metal:0.60)
                _=box(0.04,0.7,0.04,trim,SCNVector3(0,0,0.11),shield,bevel:0.01,metal:0.7)
                _=jewel(0.13,color:tint,at:SCNVector3(0,0.12,0.14),in:shield)
            }
        }
        if !preview {let marker=ring(0.72,color:team==0 ? Self.blue:Self.red,parent:root);marker.opacity=0.60;marker.name="teamRing"}
        root.scale=SCNVector3(1.12,1.12,1.12)
        return root
    }
    func surfaceTexture(stone:Bool)->UIImage {
        let format=UIGraphicsImageRendererFormat();format.scale=1
        return UIGraphicsImageRenderer(size:CGSize(width:512,height:512),format:format).image{ctx in
            UIColor(rgb:stone ? 0x6B7068:0x234A3A).setFill();ctx.fill(CGRect(x:0,y:0,width:512,height:512))
            var seed:UInt64=stone ? 81:42
            func next()->CGFloat{seed=seed &* 6364136223846793005 &+ 1;return CGFloat(seed>>32)/CGFloat(UInt32.max)}
            for _ in 0..<11000 {
                let x=next()*512,y=next()*512,t=next()
                UIColor(white:stone ? 0.25+t*0.6:0.3+t*0.5,alpha:stone ? 0.12:0.08).setFill()
                ctx.cgContext.fillEllipse(in:CGRect(x:x,y:y,width:next()*5+1,height:next()*4+1))
            }
            if stone {
                ctx.cgContext.setStrokeColor(UIColor(rgb:0x313E37).withAlphaComponent(0.6).cgColor);ctx.cgContext.setLineWidth(3)
                for row in 0..<8 {for col in -1..<6 {let x=CGFloat(col)*102+CGFloat(row%2)*51,y=CGFloat(row)*64;ctx.cgContext.stroke(CGRect(x:x+2,y:y+2,width:98,height:60))}}
            }else{
                for _ in 0..<5500 {let x=next()*512,y=next()*512;ctx.cgContext.setStrokeColor(UIColor(red:0.22+next()*0.10,green:0.37+next()*0.17,blue:0.20,alpha:0.3).cgColor);ctx.cgContext.setLineWidth(0.6);ctx.cgContext.move(to:CGPoint(x:x,y:y));ctx.cgContext.addLine(to:CGPoint(x:x+next()*3-1.5,y:y-next()*6));ctx.cgContext.strokePath()}
            }
        }
    }
    func environmentMap()->UIImage {
        let format=UIGraphicsImageRendererFormat();format.scale=1
        return UIGraphicsImageRenderer(size:CGSize(width:512,height:256),format:format).image{ctx in
            let colors=[UIColor(rgb:0x547E99).cgColor,UIColor(rgb:0xC5D9DB).cgColor,UIColor(rgb:0x3B514E).cgColor] as CFArray
            let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,0.48,1])!
            ctx.cgContext.drawLinearGradient(gradient,start:.zero,end:CGPoint(x:0,y:256),options:[])
            ctx.cgContext.setFillColor(UIColor(rgb:0xFBE2B3).cgColor);ctx.cgContext.fillEllipse(in:CGRect(x:315,y:48,width:85,height:45))
        }
    }
    func buildEnchantedTerrain(){
        let grass=surfaceTexture(stone:false),stone=surfaceTexture(stone:true),batch=SCNNode()
        let ground=mesh(SCNPlane(width:260,height:260),.white,SCNVector3(50,-0.14,-50),world);ground.eulerAngles.x = -.pi/2
        ground.geometry?.firstMaterial?.diffuse.contents=grass;ground.geometry?.firstMaterial?.diffuse.wrapS = .repeat;ground.geometry?.firstMaterial?.diffuse.wrapT = .repeat;ground.geometry?.firstMaterial?.diffuse.contentsTransform=SCNMatrix4MakeScale(28,28,1)
        for path in Battlefield.lanes {for (a,b) in zip(path,path.dropFirst()) {
            let verge=line(a,b,width:7.1,color:UIColor(rgb:0x456344),parent:batch,height:-0.07);verge.geometry?.firstMaterial?.roughness.contents=1
            let road=line(a,b,width:5.2,color:.white,parent:batch,height:-0.015),m=road.geometry!.firstMaterial!
            m.diffuse.contents=stone;m.diffuse.wrapS = .repeat;m.diffuse.wrapT = .repeat;m.diffuse.contentsTransform=SCNMatrix4MakeScale(1,Float(a.distance(b)/6),1);m.roughness.contents=0.92
            let d=(b-a).normalized,side=V2(-d.y,d.x)
            for j in 0..<max(1,Int(a.distance(b)/2.0)) {let p=a+d*(Double(j)*2)
                for sign in [-1.0,1.0]{let q=p+side*(2.8*sign);let n=box(0.32,0.14,1.6,UIColor(rgb:j%2==0 ? 0x68786B:0x566B60),SCNVector3(Float(q.x),0.03,Float(-q.y)),batch,bevel:0.07);n.eulerAngles.y=Float(atan2(d.x,-d.y))}
            }
        }}
        _=line(V2(-6,106),V2(106,-6),width:9.0,color:UIColor(rgb:0x536B58),parent:batch,height:-0.005)
        let waterGeo=SCNPlane(width:7,height:158);waterGeo.widthSegmentCount=8;waterGeo.heightSegmentCount=90
        let water=mesh(waterGeo,UIColor(rgb:0x176D72),SCNVector3(50,0.035,-50),world,metal:0.22);water.eulerAngles=SCNVector3(-Float.pi/2,0,Float.pi/4)
        waterGeo.firstMaterial?.roughness.contents=0.21
        waterGeo.shaderModifiers=[.geometry:"_geometry.position.z += sin(_geometry.position.y * 0.75 + u_time * 1.1) * 0.045 + cos(_geometry.position.x * 1.8 + u_time) * 0.022;",.surface:"float ripple = sin(_surface.diffuseTexcoord.y * 320.0 + u_time * 1.6 + sin(_surface.diffuseTexcoord.x * 23.0)) * 0.035; _surface.diffuse.rgb += float3(ripple, ripple * 1.5, ripple * 1.7);"]
        for p in [V2(12,88),V2(50,50),V2(88,12)] {
            let bridge=SCNNode();bridge.position=SCNVector3(Float(p.x),0,Float(-p.y));bridge.eulerAngles.y = -.pi/4;batch.addChildNode(bridge)
            _=box(5.7,0.26,9.4,UIColor(rgb:0x859487),SCNVector3(0,0.18,0),bridge,bevel:0.12)
            for j in -4...4{_=box(5.4,0.05,0.82,UIColor(rgb:j%2==0 ? 0x75877E:0x86948A),SCNVector3(0,0.33,Float(j)),bridge,bevel:0.04)}
            for side:Float in [-1,1]{for z:Float in [-4,0,4]{_=cylinder(0.20,0.90,UIColor(rgb:0x6C8078),SCNVector3(side*3,0.52,z),bridge);_=sphere(0.24,Self.gold,SCNVector3(side*3,1.0,z),bridge,scale:SCNVector3(1,0.45,1))};_=box(0.16,0.17,8.6,UIColor(rgb:0x7F9288),SCNVector3(side*3,0.77,0),bridge,bevel:0.04)}
        }
        for (i,rock) in Battlefield.rocks.enumerated(){for j in 0..<3 {
            let r=Float(rock.radius)*Float(j==0 ? 0.72:0.52),h=r*1.22
            let n=mesh(sculpt([(0,r*0.75,r*0.83),(h*0.23,r,r*0.9),(h*0.68,r*0.90,r*0.67),(h,r*0.30,r*0.29)],sides:7),UIColor(rgb:(i+j)%2==0 ? 0x4D615B:0x687A6B),SCNVector3(Float(rock.position.x)+Float(j-1)*1.25,0,Float(-rock.position.y)+Float(j%2)*0.7),batch);n.eulerAngles.y=Float(i+j)*1.37
            _=sphere(CGFloat(r*0.48),UIColor(rgb:0x3F633E),SCNVector3(0,h*0.84,0),n,scale:SCNVector3(1.2,0.20,0.9))
        }}
        for (i,p) in Battlefield.brush.enumerated(){
            _=cylinder(3.4,0.03,UIColor(rgb:0x244732),SCNVector3(Float(p.x),0.01,Float(-p.y)),batch)
            for j in 0..<65{let a=Double(j)*2.399,r=sqrt(Double(j)/65)*3.0;fern(at:V2(p.x+cos(a)*r,p.y+sin(a)*r),scale:0.55+Double(j%4)*0.16,color:UIColor(rgb:(i+j)%3==0 ? 0x81915B:0x527446),parent:batch)}
        }
        for i in 0..<200 {
            let p=V2(Double((i*37+11)%116)-8,Double((i*61+7)%116)-8)
            if Battlefield.lanes.contains(where:{path in zip(path,path.dropFirst()).contains{segmentDistance(p,$0,$1)<7}}) || abs(p.x+p.y-100)<11 || Battlefield.brush.contains(where:{$0.distance(p)<5}) || [V2(35,65),V2(65,35)].contains(where:{$0.distance(p)<8}) || Battlefield.bases.contains(where:{$0.distance(p)<10}) {continue}
            enchantedTree(p,scale:0.78+Double(i%4)*0.17,parent:batch)
        }
        // Distant woodland covers the camera edges without restricting camera follow.
        for i in 0..<72 {let a=Double(i)*2 * .pi/72;let p=V2(50+cos(a)*82,50+sin(a)*82);enchantedTree(p,scale:1.7+Double(i%3)*0.3,parent:batch)}
        for team in 0...1 {
            let p=Battlefield.bases[team],color=team==0 ? Self.blue:Self.red,root=SCNNode();root.position=SCNVector3(Float(p.x),0,Float(-p.y));batch.addChildNode(root)
            _=cylinder(7.4,0.18,UIColor(rgb:0x405955),SCNVector3(0,0,0),root);_=cylinder(6.5,0.20,UIColor(rgb:0x75877B),SCNVector3(0,0.08,0),root)
            for r in [4.8,6.25]{_=ring(r,color:color.withAlphaComponent(0.55),parent:root,height:0.20)}
            for j in 0..<12{let a=Double(j) * .pi/6;let n=box(0.055,0.025,0.80,Self.gold,SCNVector3(Float(cos(a)*5.5),0.20,Float(sin(a)*5.5)),root,bevel:0.005);n.eulerAngles.y=Float(-a + .pi/2)}
        }
        for p in [V2(35,65),V2(65,35)] {
            let root=SCNNode();root.position=SCNVector3(Float(p.x),0.06,Float(-p.y));batch.addChildNode(root)
            _=cylinder(5.5,0.15,UIColor(rgb:0x3B5D59),SCNVector3Zero,root);_=ring(5.1,color:Self.gold.withAlphaComponent(0.4),parent:root,height:0.15)
            for j in 0..<8 {let a=Double(j) * .pi/4;let n=mesh(sculpt([(0,0.55,0.50),(1.9,0.4,0.35),(2.2,0.3,0.26)],sides:6),UIColor(rgb:0x697B71),SCNVector3(Float(cos(a)*5.5),0,Float(sin(a)*5.5)),root);_=jewel(0.22,color:Self.blue,at:SCNVector3(0,2.45,0),in:n)}
        }
        mergeStaticMaterials(batch);world.addChildNode(batch.flattenedClone())
    }
    func mergeStaticMaterials(_ root:SCNNode){
        var cache:[String:SCNMaterial]=[:]
        root.enumerateChildNodes{node,_ in guard let geometry=node.geometry else{return};geometry.materials=geometry.materials.map{m in
            guard let color=m.diffuse.contents as? UIColor else{return m}
            var red:CGFloat=0,green:CGFloat=0,blue:CGFloat=0,alpha:CGFloat=0;color.getRed(&red,green:&green,blue:&blue,alpha:&alpha)
            let key="\(red),\(green),\(blue),\(alpha),\(m.metalness.contents ?? 0),\(m.roughness.contents ?? 1),\(m.emission.contents ?? 0),\(m.emission.intensity),\(m.isDoubleSided)"
            if let shared=cache[key]{return shared};cache[key]=m;return m
        }}
    }
    func fern(at p:V2,scale:Double,color:UIColor,parent:SCNNode){
        var vertices:[SCNVector3]=[];var idx:[Int32]=[]
        for blade in 0..<5 {let a=Float(blade)*2.4;let h=Float(scale)*(0.65+Float(blade%3)*0.15),base=Int32(vertices.count),dx=cos(a),dz=sin(a)
            vertices += [SCNVector3(-dz*0.07,0,dx*0.07),SCNVector3(dz*0.07,0,-dx*0.07),SCNVector3(dx*0.18,h*0.70,dz*0.18),SCNVector3(dx*0.48,h,dz*0.48)];idx += [base,base+1,base+2,base+1,base+3,base+2]
        }
        let g=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:vertices.map{_ in SCNVector3(0,1,0)})],elements:[SCNGeometryElement(indices:idx,primitiveType:.triangles)])
        let n=mesh(g,color,SCNVector3(Float(p.x),0.04,Float(-p.y)),parent);n.geometry?.firstMaterial?.isDoubleSided=true
    }
    func enchantedTree(_ p:V2,scale:Double,parent:SCNNode){
        let root=SCNNode();root.position=SCNVector3(Float(p.x),0,Float(-p.y));let s=Float(scale);root.scale=SCNVector3(s,s,s);parent.addChildNode(root)
        _=mesh(sculpt([(0,0.52,0.42),(0.25,0.3,0.28),(2.0,0.15,0.18),(3.2,0.07,0.08)],sides:8),UIColor(rgb:0x4D4936),SCNVector3Zero,root)
        for i in 0..<6{let a=Float(i)*2.4,n=sphere(1.2,UIColor(rgb:i%3==0 ? 0x466A43:i%3==1 ? 0x365A40:0x567B49),SCNVector3(cos(a)*0.85,2.8+Float(i%3)*0.55,sin(a)*0.85),root,scale:SCNVector3(1.25,0.62,1));n.geometry?.firstMaterial?.roughness.contents=0.95}
        for j in 0..<3{fern(at:V2(p.x+Double(j)-1,p.y+0.7),scale:0.65,color:UIColor(rgb:0x66824C),parent:parent)}
    }
}
extension UIColor {
    func darker(_ amount:CGFloat)->UIColor {var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0;getRed(&r,green:&g,blue:&b,alpha:&a);return UIColor(red:r*(1-amount),green:g*(1-amount),blue:b*(1-amount),alpha:a)}
}
