import SceneKit
import UIKit

extension UIColor {
    convenience init(rgb:UInt32,alpha:CGFloat=1){self.init(red:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,blue:CGFloat(rgb&255)/255,alpha:alpha)}
}
final class ArenaRenderer {
    let scene=SCNScene();let camera=SCNNode();let world=SCNNode();let actors=SCNNode();let fxRoot=SCNNode();let aimRoot=SCNNode()
    var nodes:[Int:SCNNode]=[:];var fxNodes:[Int:SCNNode]=[:];var cameraPoint=V2(8,8);var panPoint:V2?;var highQuality=true
    private var pet=SCNNode();private var ambient=SCNNode();private var sun=SCNNode();private var aimStamp=""
    static let gold=UIColor(rgb:0xD4B578);static let blue=UIColor(rgb:0x50CEFA);static let red=UIColor(rgb:0xF17980)
    init(){
        scene.rootNode.addChildNode(world);scene.rootNode.addChildNode(actors);scene.rootNode.addChildNode(fxRoot);scene.rootNode.addChildNode(aimRoot)
        scene.background.contents=UIColor(rgb:0x192E35);scene.fogColor=UIColor(rgb:0x405D58);scene.fogStartDistance=62;scene.fogEndDistance=125
        camera.camera=SCNCamera();camera.camera?.fieldOfView=48;camera.camera?.zNear=0.3;camera.camera?.zFar=180;camera.camera?.wantsHDR=true;camera.camera?.bloomIntensity=0.18;camera.camera?.bloomThreshold=1;camera.camera?.exposureOffset=0.1;scene.rootNode.addChildNode(camera)
        ambient.light=SCNLight();ambient.light?.type = .ambient;ambient.light?.color=UIColor(rgb:0xA4C6D3);ambient.light?.intensity=650;scene.rootNode.addChildNode(ambient)
        sun.light=SCNLight();sun.light?.type = .directional;sun.light?.color=UIColor(rgb:0xFFE4BE);sun.light?.intensity=1400;sun.light?.castsShadow=true;sun.light?.shadowMode = .deferred;sun.light?.shadowColor=UIColor.black.withAlphaComponent(0.35);sun.light?.shadowMapSize=CGSize(width:2048,height:2048);sun.light?.orthographicScale=60;sun.light?.maximumShadowDistance=70;sun.eulerAngles=SCNVector3(-Float.pi/3,-Float.pi/5,0);scene.rootNode.addChildNode(sun)
        buildTerrain();pet=makePet();actors.addChildNode(pet)
    }
    func material(_ color:UIColor,metal:CGFloat=0,rough:CGFloat=0.8,glow:Bool=false)->SCNMaterial {
        let m=SCNMaterial();m.diffuse.contents=color;m.lightingModel = .physicallyBased;m.metalness.contents=metal;m.roughness.contents=rough
        if glow{m.emission.contents=color;m.emission.intensity=0.6};return m
    }
    @discardableResult func mesh(_ geometry:SCNGeometry,_ color:UIColor,_ p:SCNVector3=SCNVector3Zero,_ parent:SCNNode,metal:CGFloat=0,glow:Bool=false)->SCNNode {
        geometry.materials=[material(color,metal:metal,glow:glow)];let n=SCNNode(geometry:geometry);n.position=p;parent.addChildNode(n);return n
    }
    func sphere(_ radius:CGFloat,_ color:UIColor,_ p:SCNVector3,_ parent:SCNNode,scale:SCNVector3=SCNVector3(1,1,1),glow:Bool=false)->SCNNode {
        let g=SCNSphere(radius:radius);g.segmentCount=12;let n=mesh(g,color,p,parent,glow:glow);n.scale=scale;return n
    }
    func box(_ w:CGFloat,_ h:CGFloat,_ l:CGFloat,_ color:UIColor,_ p:SCNVector3,_ parent:SCNNode,bevel:CGFloat=0.06,metal:CGFloat=0)->SCNNode{mesh(SCNBox(width:w,height:h,length:l,chamferRadius:bevel),color,p,parent,metal:metal)}
    func cylinder(_ r:CGFloat,_ h:CGFloat,_ color:UIColor,_ p:SCNVector3,_ parent:SCNNode,glow:Bool=false)->SCNNode {let g=SCNCylinder(radius:r,height:h);g.radialSegmentCount=16;return mesh(g,color,p,parent,glow:glow)}
    func ring(_ radius:Double,color:UIColor,parent:SCNNode,height:Float=0.04)->SCNNode {let g=SCNTorus(ringRadius:CGFloat(radius),pipeRadius:0.035);g.ringSegmentCount=48;g.pipeSegmentCount=4;return mesh(g,color,SCNVector3(0,height,0),parent,glow:true)}
    func line(_ a:V2,_ b:V2,width:Double,color:UIColor,parent:SCNNode,height:Float=0.015)->SCNNode {
        let d=b-a;let n=box(CGFloat(width),0.025,CGFloat(d.length),color,SCNVector3(Float((a.x+b.x)/2),height,Float(-(a.y+b.y)/2)),parent,bevel:0);n.eulerAngles.y=Float(atan2(d.x,d.y));return n
    }
    func terrainTexture()->UIImage {
        let size=CGSize(width:512,height:512);return UIGraphicsImageRenderer(size:size).image{ctx in
            UIColor(rgb:0x395B3F).setFill();ctx.fill(CGRect(origin:.zero,size:size));var seed:UInt64=42
            for _ in 0..<20000 {seed=seed &* 1664525 &+ 1013904223;let x=CGFloat(seed%512);seed=seed &* 1664525 &+ 1013904223;let y=CGFloat(seed%512);let tone=CGFloat(seed%55)/255;UIColor(red:0.17+tone,green:0.27+tone,blue:0.17+tone*0.7,alpha:0.45).setFill();ctx.fill(CGRect(x:x,y:y,width:CGFloat(seed%3+1),height:CGFloat(seed%4+1)))}
        }
    }
    func buildTerrain(){
        let g=SCNPlane(width:110,height:110);let terrain=mesh(g,UIColor.white,SCNVector3(50,-0.12,-50),world);terrain.eulerAngles.x = -.pi/2;terrain.geometry?.firstMaterial?.diffuse.contents=terrainTexture();terrain.geometry?.firstMaterial?.diffuse.wrapS = .repeat;terrain.geometry?.firstMaterial?.diffuse.wrapT = .repeat;terrain.geometry?.firstMaterial?.diffuse.contentsTransform=SCNMatrix4MakeScale(8,8,1)
        let staticWorld=SCNNode()
        for path in Battlefield.lanes {for (a,b) in zip(path,path.dropFirst()) {
            _=line(a,b,width:5.8,color:UIColor(rgb:0x65715B),parent:staticWorld)
            let len=a.distance(b);let count=max(1,Int(len/2));for i in 0..<count {let p=a+(b-a)*(Double(i)/Double(count));let tile=box(1.6,0.03,1.1,UIColor(rgb:i%3==0 ? 0x879082:0x788674),SCNVector3(Float(p.x),0.03,Float(-p.y)),staticWorld,bevel:0.1);tile.eulerAngles.y=Float(atan2(b.x-a.x,b.y-a.y));tile.opacity=0.65}
        }}
        // A river cuts diagonally through the jungle; shallow stone crossings meet each lane.
        let river=line(V2(7,93),V2(93,7),width:7,color:UIColor(rgb:0x327E88),parent:staticWorld,height:0.055);river.geometry?.firstMaterial?.roughness.contents=0.22;river.geometry?.firstMaterial?.metalness.contents=0.30
        for p in [V2(12,88),V2(50,50),V2(88,12)] {let bridge=box(8,0.15,5.7,UIColor(rgb:0x969D87),SCNVector3(Float(p.x),0.15,Float(-p.y)),staticWorld,bevel:0.15);bridge.eulerAngles.y = -.pi/4}
        for (i,rock) in Battlefield.rocks.enumerated() {
            for j in 0..<3 {let p=SCNVector3(Float(rock.position.x)+Float(j-1)*1.2,Float(rock.radius)*0.35,Float(-rock.position.y));let r=sphere(CGFloat(rock.radius*0.65),UIColor(rgb:j==0 ? 0x61746A:0x6F7C70),p,staticWorld,scale:SCNVector3(1,0.72,0.83));r.eulerAngles=SCNVector3(Float(i)*0.4,Float(j)*1.1,0.2)}
        }
        for (i,p) in Battlefield.brush.enumerated(){
            _=cylinder(3.4,0.06,UIColor(rgb:0x284C34),SCNVector3(Float(p.x),0.08,Float(-p.y)),staticWorld)
            for j in 0..<23 {let angle=Double(j)*2.4;let radius=Double(j%5)*0.58;let g=SCNCone(topRadius:0.025,bottomRadius:0.16,height:0.8+CGFloat(j%3)*0.25);g.radialSegmentCount=4;let blade=mesh(g,UIColor(rgb:(i+j)%2==0 ? 0x5F984C:0x7AA656),SCNVector3(Float(p.x+cos(angle)*radius),0.55,Float(-p.y+sin(angle)*radius)),staticWorld);blade.eulerAngles.z=Float(j%3-1)*0.15}
        }
        for i in 0..<90 {
            let x=Double((i*37+11)%96)+2;let y=Double((i*61+7)%96)+2;let p=V2(x,y)
            if Battlefield.lanes.contains(where:{path in zip(path,path.dropFirst()).contains{segmentDistance(p,$0,$1)<7}}) || abs(x+y-100)<12 || Battlefield.brush.contains(where:{$0.distance(p)<5}) || [V2(35,65),V2(65,35)].contains(where:{$0.distance(p)<8}) {continue}
            makeTree(p,scale:0.8+Double(i%3)*0.18,parent:staticWorld)
        }
        for team in 0...1 {
            let p=Battlefield.bases[team];_=cylinder(6.5,0.2,UIColor(rgb:0x6C817A),SCNVector3(Float(p.x),0.1,Float(-p.y)),staticWorld)
            let ringRoot=SCNNode();ringRoot.position=SCNVector3(Float(p.x),0.22,Float(-p.y));_=ring(5.8,color:team==0 ? Self.blue:Self.red,parent:ringRoot);staticWorld.addChildNode(ringRoot)
            for i in 0..<8{let a=Double(i) * .pi / 4;let pos=SCNVector3(Float(p.x+cos(a)*6),0.5,Float(-p.y+sin(a)*6));_=box(0.6,1,0.6,UIColor(rgb:0x89948E),pos,staticWorld,bevel:0.15)}
        }
        for p in [V2(35,65),V2(65,35)] {let root=SCNNode();root.position=SCNVector3(Float(p.x),0.08,Float(-p.y));_=cylinder(5.2,0.15,UIColor(rgb:0x567C79),SCNVector3Zero,root);_=ring(5,color:Self.gold.withAlphaComponent(0.8),parent:root,height:0.12);staticWorld.addChildNode(root)}
        world.addChildNode(staticWorld.flattenedClone())
        let border=SCNNode();for p in [V2(-1,50),V2(101,50)] {_=box(2,2,105,UIColor(rgb:0x304C3B),SCNVector3(Float(p.x),0.6,Float(-p.y)),border)};for p in [V2(50,-1),V2(50,101)]{_=box(105,2,2,UIColor(rgb:0x304C3B),SCNVector3(Float(p.x),0.6,Float(-p.y)),border)};world.addChildNode(border.flattenedClone())
    }
    func segmentDistance(_ p:V2,_ a:V2,_ b:V2)->Double{let d=b-a;let t=max(0,min(1,(p-a).dot(d)/max(0.001,d.dot(d))));return p.distance(a+d*t)}
    func makeTree(_ p:V2,scale:Double,parent:SCNNode){
        let root=SCNNode();root.position=SCNVector3(Float(p.x),0,Float(-p.y));root.scale=SCNVector3(Float(scale),Float(scale),Float(scale))
        _=cylinder(0.28,3,UIColor(rgb:0x695B45),SCNVector3(0,1.5,0),root)
        for i in 0..<4 {_=sphere(1.6,UIColor(rgb:i%2==0 ? 0x426F4A:0x527E50),SCNVector3(Float(i%2)*1.1-0.5,3+Float(i%3)*0.5,Float(i/2)*0.8-0.4),root,scale:SCNVector3(1,0.85,1))};parent.addChildNode(root)
    }
    func makeHero(_ def:HeroDef,team:Int,preview:Bool=false)->SCNNode {
        let root=SCNNode();let body=SCNNode();body.name="body";root.addChildNode(body)
        let cloth=UIColor(rgb:def.color);let dark=UIColor(rgb:0x243849);let steel=UIColor(rgb:0xADBCC0);let skin=UIColor(rgb:def.id%3==0 ? 0xCFA382:0xE8C0A3);let trim=Self.gold
        let heavy=def.role == .tank;let magic=def.role == .mage || def.role == .support;let width:CGFloat=heavy ? 0.98:0.68
        for side in [-1.0,1.0] {
            let leg=SCNNode();leg.name=side<0 ? "legL":"legR";leg.position=SCNVector3(Float(side)*Float(width)*0.27,0.87,0);body.addChildNode(leg)
            _=mesh(SCNCapsule(capRadius:heavy ? 0.17:0.125,height:0.78),dark,SCNVector3(0,-0.26,0),leg)
            _=box(heavy ? 0.35:0.27,0.29,0.44,steel,SCNVector3(0,-0.68,0.07),leg,bevel:0.07,metal:0.65)
            let kneepad=sphere(0.17,trim,SCNVector3(0,-0.31,0.14),leg,scale:SCNVector3(1,0.85,0.35));kneepad.geometry?.firstMaterial?.metalness.contents=0.7
        }
        _=box(width,0.78,0.42,cloth,SCNVector3(0,1.22,0),body,bevel:0.15,metal:heavy ? 0.7:0.2)
        _=box(width*0.83,0.57,0.08,heavy ? steel:dark,SCNVector3(0,1.27,0.24),body,bevel:0.08,metal:0.55)
        _=box(width*1.03,0.12,0.48,trim,SCNVector3(0,0.94,0),body,bevel:0.025,metal:0.8)
        let gem=sphere(0.10,cloth,SCNVector3(0,1.47,0.31),body,scale:SCNVector3(0.75,1.25,0.5),glow:true);gem.name="gem"
        // A sculpted cloth panel, made from triangles, forms the cape behind each hero.
        let verts:[SCNVector3]=[SCNVector3(-Float(width)/2,1.57,-0.20),SCNVector3(Float(width)/2,1.57,-0.20),SCNVector3(-Float(width)*0.8,0.28,-0.52),SCNVector3(0,0.20,-0.67),SCNVector3(Float(width)*0.8,0.28,-0.52)]
        let element=SCNGeometryElement(indices:[Int32(0),1,3,0,3,2,1,4,3],primitiveType:.triangles);let cape=SCNGeometry(sources:[SCNGeometrySource(vertices:verts)],elements:[element]);cape.materials=[material(cloth)];cape.firstMaterial?.isDoubleSided=true;let capenode=SCNNode(geometry:cape);capenode.name="cape";body.addChildNode(capenode)
        let head=SCNNode();head.position=SCNVector3(0,1.87,0);body.addChildNode(head)
        _=sphere(0.25,skin,SCNVector3Zero,head,scale:SCNVector3(0.82,1,0.87))
        let hairColor=UIColor(rgb:def.id%3==0 ? 0xDEDAC8:def.id%3==1 ? 0x593B32:0x323047)
        _=sphere(0.255,heavy ? steel:hairColor,SCNVector3(0,0.12,-0.035),head,scale:SCNVector3(0.92,0.70,1))
        for side in [-1.0,1.0] {
            _=sphere(0.025,UIColor(rgb:0x16202A),SCNVector3(Float(side)*0.085,0.015,0.205),head,scale:SCNVector3(1.3,0.8,0.55))
            _=sphere(0.03,skin,SCNVector3(Float(side)*0.205,-0.005,0),head,scale:SCNVector3(1,1.6,0.65))
            let arm=SCNNode();arm.name=side<0 ? "armL":"armR";arm.position=SCNVector3(Float(side)*Float(width)*0.64,1.46,0);body.addChildNode(arm)
            _=sphere(heavy ? 0.27:0.19,heavy ? steel:cloth,SCNVector3Zero,arm,scale:SCNVector3(1.1,0.85,1))
            _=mesh(SCNCapsule(capRadius:heavy ? 0.145:0.105,height:0.61),cloth,SCNVector3(Float(side)*0.03,-0.29,0.02),arm)
            _=sphere(0.12,skin,SCNVector3(Float(side)*0.05,-0.60,0.06),arm)
        }
        if magic {let crown=mesh(SCNTorus(ringRadius:0.26,pipeRadius:0.025),trim,SCNVector3(0,0.23,0),head,metal:0.9);crown.eulerAngles.x=0.12;for i in -1...1 {_=mesh(SCNCone(topRadius:0,bottomRadius:0.05,height:0.22),trim,SCNVector3(Float(i)*0.13,0.31,0.16),head,metal:0.8)}}
        let weapon=SCNNode();weapon.name="weapon";weapon.position=SCNVector3(Float(width)*0.70,0.88,0.13);body.addChildNode(weapon)
        if magic {
            _=cylinder(0.045,1.7,trim,SCNVector3(0,0.45,0),weapon)
            _=sphere(0.17,cloth,SCNVector3(0,1.38,0),weapon,glow:true);_=ring(0.25,color:trim,parent:weapon,height:1.38)
        }else if def.role == .marksman {
            if def.id==10 {_=box(0.17,0.2,1.12,dark,SCNVector3(0,0.15,0.35),weapon,metal:0.75);_=cylinder(0.08,0.45,trim,SCNVector3(0,0.24,0.35),weapon)}else {let bow=mesh(SCNTorus(ringRadius:0.50,pipeRadius:0.045),trim,SCNVector3(0,0.38,0.05),weapon,metal:0.8);bow.scale=SCNVector3(0.52,1,1);bow.eulerAngles.x = .pi/2;_=box(0.025,1,0.025,UIColor.white,SCNVector3(0,0.35,0),weapon,bevel:0)}
        }else {
            let blade=box(heavy ? 0.22:0.12,def.role == .assassin ? 0.66:1.3,0.055,steel,SCNVector3(0,0.64,0),weapon,bevel:0.02,metal:0.9);blade.eulerAngles.z = -0.18
            _=box(0.40,0.07,0.12,trim,SCNVector3(0,0.12,0),weapon,metal:0.8)
            if heavy {let shield=box(0.62,0.92,0.12,cloth,SCNVector3(-Float(width)*0.72,1.08,0.30),body,bevel:0.12,metal:0.7);_=box(0.09,0.72,0.05,trim,SCNVector3(0,0,0.09),shield,metal:0.8)}
        }
        if !preview {let marker=ring(0.78,color:team==0 ? Self.blue:Self.red,parent:root);marker.opacity=0.72}
        root.scale=SCNVector3(1.3,1.3,1.3)
        return root
    }
    func makePet()->SCNNode{let root=SCNNode();_=sphere(0.32,UIColor(rgb:0xE5D7BA),SCNVector3(0,0.40,0),root,scale:SCNVector3(0.8,0.85,1.4));_=sphere(0.25,UIColor(rgb:0xFFF0CE),SCNVector3(0,0.58,0.30),root)
        for side in [-1.0,1.0] {let ear=mesh(SCNCone(topRadius:0,bottomRadius:0.12,height:0.38),UIColor(rgb:0xE5BB89),SCNVector3(Float(side)*0.15,0.86,0.27),root);ear.eulerAngles.z=Float(-side)*0.2;_=sphere(0.045,UIColor(rgb:0x326A86),SCNVector3(Float(side)*0.095,0.61,0.515),root);for z in [-0.2,0.22]{_=cylinder(0.065,0.21,UIColor(rgb:0xE5BB89),SCNVector3(Float(side)*0.15,0.17,Float(z)),root)}}
        _=sphere(0.17,Self.blue,SCNVector3(0,0.6,-0.53),root,scale:SCNVector3(0.65,0.6,1.8),glow:true);return root}
    func makeUnit(_ u:ArenaUnit)->SCNNode {
        if u.isHero {let n=makeHero(u.def,team:u.team);addHealth(n,u);return n}
        let root=SCNNode();let color=u.team==0 ? Self.blue:u.team==1 ? Self.red:UIColor(rgb:0xB3A277);let stone=UIColor(rgb:0x7A8A89)
        if u.structure {
            _=cylinder(u.kind == .core ? 2.8:1.35,0.45,stone,SCNVector3(0,0.22,0),root)
            _=cylinder(u.kind == .core ? 1.8:0.7,2.4,UIColor(rgb:0x526E75),SCNVector3(0,1.55,0),root)
            for side in [-1.0,1.0] {_=box(0.35,2.5,0.45,Self.gold,SCNVector3(Float(side)*0.68,1.55,0),root,metal:0.6)}
            let crystal=mesh(SCNCone(topRadius:0,bottomRadius:u.kind == .core ? 1.3:0.55,height:u.kind == .core ? 3.2:1.4),color,SCNVector3(0,u.kind == .core ? 4.0:3.3,0),root,metal:0.35,glow:true);crystal.name="crystal";_=ring(u.range,color:color.withAlphaComponent(0.18),parent:root)
        }else if u.neutral || u.kind == .summoned {
            let big=u.kind != .camp;let scale:Float=big ? 1.65:1
            let body=SCNNode();body.name="body";root.addChildNode(body);body.scale=SCNVector3(scale,scale,scale)
            let tint=UIColor(rgb:u.kind == .sentinel ? 0x4CACA0:u.kind == .colossus || u.kind == .summoned ? 0x9682CD:u.tier==1 ? 0x4A91BF:0xAA7254)
            _=sphere(1,tint,SCNVector3(0,1.1,0),body,scale:SCNVector3(1,0.9,1.2));_=sphere(0.5,stone,SCNVector3(0,1.8,0.8),body)
            for side in [-1.0,1.0] {for z in [-0.65,0.65] {_=mesh(SCNCapsule(capRadius:0.3,height:1.2),tint,SCNVector3(Float(side)*0.75,0.6,Float(z)),body)};_=sphere(0.075,Self.gold,SCNVector3(Float(side)*0.2,1.88,1.23),body,glow:true);let horn=mesh(SCNCone(topRadius:0,bottomRadius:0.14,height:0.8),Self.gold,SCNVector3(Float(side)*0.35,2.33,0.73),body);horn.eulerAngles.z=Float(-side)*0.3}
            if u.kind == .sentinel {_=sphere(0.95,UIColor(rgb:0x376C65),SCNVector3(0,1.65,-0.1),body,scale:SCNVector3(1.25,0.50,1.35))}
            else {for i in -2...2 {let crystal=mesh(SCNCone(topRadius:0,bottomRadius:0.17,height:0.85),tint,SCNVector3(Float(i)*0.35,2.0,-0.25),body,glow:true);crystal.eulerAngles.z=Float(i)*0.2}}
        }else{
            let siege=u.kind == .siege;_=box(siege ? 0.9:0.55,siege ? 0.7:0.8,siege ? 1.1:0.55,UIColor(rgb:0x54626A),SCNVector3(0,0.65,0),root)
            _=sphere(0.24,color,SCNVector3(0,1.2,0),root);_=box(0.64,0.25,0.38,color,SCNVector3(0,0.92,0),root)
            if siege {_=box(0.20,0.20,1.2,Self.gold,SCNVector3(0,1.0,0.55),root,metal:0.7);for x in [-0.55,0.55]{_=sphere(0.26,stone,SCNVector3(Float(x),0.35,0),root)}}else {for x in [-0.17,0.17]{_=box(0.15,0.35,0.22,stone,SCNVector3(Float(x),0.21,0),root)}}
        }
        addHealth(root,u);return root
    }
    func addHealth(_ root:SCNNode,_ u:ArenaUnit){
        let hud=SCNNode();hud.name="health";hud.position=SCNVector3(0,u.isHero ? 2.5:u.structure ? 5.4:u.neutral || u.kind == .summoned ? 4.5:1.7,0)
        let billboard=SCNBillboardConstraint();billboard.freeAxes = .all;hud.constraints=[billboard]
        let width:CGFloat=u.structure ? 3:u.isHero ? 1.7:1.25
        _=box(width,0.14,0.015,UIColor.black.withAlphaComponent(0.8),SCNVector3Zero,hud,bevel:0)
        let fill=box(width-0.04,0.10,0.02,u.team==0 ? UIColor(rgb:0x66E0A0):u.team==1 ? Self.red:Self.gold,SCNVector3(0,0,0.025),hud,bevel:0);fill.name="fill";fill.geometry?.firstMaterial?.lightingModel = .constant
        if u.isHero {let text=SCNText(string:u.name,extrusionDepth:0);text.font=UIFont.systemFont(ofSize:0.27,weight:.semibold);text.flatness=0.2;text.firstMaterial=material(UIColor.white);text.firstMaterial?.lightingModel = .constant;let n=SCNNode(geometry:text);let bounds=text.boundingBox;n.position=SCNVector3(-(bounds.max.x-bounds.min.x)/2,0.15,0);hud.addChildNode(n)}
        root.addChildNode(hud)
    }
    func update(_ game:ArenaSimulation,dt:Double){
        let ids=Set(game.units.map(\.id));for id in Array(nodes.keys) where !ids.contains(id){nodes[id]?.removeFromParentNode();nodes.removeValue(forKey:id)}
        for u in game.units {
            let n:SCNNode;if let existing=nodes[u.id]{n=existing}else{n=makeUnit(u);n.name="unit-\(u.id)";nodes[u.id]=n;actors.addChildNode(n)}
            n.isHidden = !u.alive || !game.visible(u,to:0)
            if u.structure && !u.alive{n.isHidden=false;n.opacity=0.20;n.scale=SCNVector3(1,0.2,1);n.childNode(withName:"health",recursively:false)?.isHidden=true}
            n.position=SCNVector3(Float(u.p.x),0,Float(-u.p.y))
            if !u.structure {let rotation=Float(atan2(u.facing.x,-u.facing.y));n.eulerAngles.y=rotation}
            let moving=u.p.distance(u.lastPosition)>0.005;let stride=Float(sin(game.time*11+Double(u.id)))*(moving ? 0.5:0.015)
            if let body=n.childNode(withName:"body",recursively:false){body.position.y=moving ? abs(stride)*0.07:Float(sin(game.time*2+Double(u.id)))*0.025;body.childNode(withName:"legL",recursively:false)?.eulerAngles.x=stride;body.childNode(withName:"legR",recursively:false)?.eulerAngles.x = -stride;body.childNode(withName:"armL",recursively:false)?.eulerAngles.x = -stride*0.65;body.childNode(withName:"armR",recursively:false)?.eulerAngles.x=u.attackPose>0 ? -1.1:stride*0.65;body.childNode(withName:"weapon",recursively:false)?.eulerAngles.x=u.attackPose>0 ? -0.8:0;body.childNode(withName:"cape",recursively:false)?.eulerAngles.x=Float(sin(game.time*4))*0.04}
            if let bar=n.childNode(withName:"fill",recursively:true){bar.scale.x=Float(max(0,u.hp/u.maxHP))}
            if let crystal=n.childNode(withName:"crystal",recursively:false){crystal.eulerAngles.y=Float(game.time*0.4);crystal.position.y += Float(sin(game.time*2)*0.001)}
            let shield=n.childNode(withName:"shieldBubble",recursively:false)
            if u.shield>0 {if shield==nil {let s=sphere(1.1,Self.blue.withAlphaComponent(0.15),SCNVector3(0,1.15,0),n,scale:SCNVector3(1,1.25,1),glow:true);s.name="shieldBubble";s.geometry?.firstMaterial?.transparency=0.20}}else{shield?.removeFromParentNode()}
            if u.id==game.playerID {n.opacity=u.conceal>0 || Battlefield.inBrush(u.p) != nil ? 0.62:1}
        }
        let target=panPoint ?? game.player.p;cameraPoint=cameraPoint+(target-cameraPoint)*min(1,dt*8)
        camera.position=SCNVector3(Float(cameraPoint.x),30,Float(-cameraPoint.y)+23);camera.look(at:SCNVector3(Float(cameraPoint.x),0,Float(-cameraPoint.y)))
        pet.isHidden = !game.player.alive;let petTarget=game.player.p+V2(-1.5,-1.6);pet.position=SCNVector3(Float(petTarget.x),Float(sin(game.time*5))*0.05,Float(-petTarget.y));pet.eulerAngles.y=Float(atan2(game.player.facing.x,-game.player.facing.y))
        updateEffects(game);updateAim(game)
    }
    func updateEffects(_ game:ArenaSimulation){
        let ids=Set(game.effects.map(\.id));for id in Array(fxNodes.keys) where !ids.contains(id){fxNodes[id]?.removeFromParentNode();fxNodes.removeValue(forKey:id)}
        for f in game.effects {
            let root:SCNNode
            if let n=fxNodes[f.id]{root=n}else{
                root=SCNNode();root.position=SCNVector3(Float(f.a.x),0.2,Float(-f.a.y));let c=f.team==0 ? Self.blue:f.team==1 ? Self.red:Self.gold
                switch f.kind {
                case "damage":
                    // Only render local combat numbers, keeping distant battles inexpensive.
                    if f.a.distance(game.player.p)<18 {let text=SCNText(string:String(Int(f.value)),extrusionDepth:0);text.font=UIFont.systemFont(ofSize:0.42,weight:.bold);text.flatness=0.3;text.firstMaterial=material(f.team==0 ? Self.gold:Self.red);text.firstMaterial?.lightingModel = .constant;let n=SCNNode(geometry:text);n.constraints=[SCNBillboardConstraint()];n.position=SCNVector3(-0.25,2.3,0);root.addChildNode(n)}
                case "projectile":_=sphere(f.value>0 ? 0.18:0.10,c,SCNVector3(0,1,0),root,glow:true)
                case "meteor":_=sphere(1,c,SCNVector3(0,0.3,0),root,scale:SCNVector3(Float(f.value),0.35,Float(f.value)),glow:true);_=ring(f.value,color:c,parent:root)
                case "warning":_=ring(f.value,color:Self.red,parent:root)
                case "heal":_=ring(1.2,color:UIColor.systemGreen,parent:root)
                case "hook","cast","slash","critical","cone":let end=f.b-f.a;_=line(.zero,end,width:f.kind=="cone" ? 0.3:0.09,color:c,parent:root,height:0.8)
                default:_=ring(f.value>0 ? min(7,f.value):2,color:c,parent:root)
                }
                fxRoot.addChildNode(root);fxNodes[f.id]=root
            }
            let progress=Float(1-f.ttl/f.duration);root.opacity=CGFloat(1-progress);if f.kind=="damage"{root.position.y=0.2+progress*1.5}else if f.kind != "projectile" && f.kind != "warning" {let s=0.6+progress*0.5;root.scale=SCNVector3(s,s,s)}
        }
    }
    func updateAim(_ game:ArenaSimulation){
        aimRoot.childNodes.forEach{$0.removeFromParentNode()};guard game.player.alive else{return};let p=game.player
        aimRoot.position=SCNVector3(Float(p.p.x),0.14,Float(-p.p.y))
        if let i=game.aimingSkill {let spec=p.def.abilities[i];let d=(game.aim ?? p.facing).normalized
            _=ring(spec.range,color:Self.blue.withAlphaComponent(0.40),parent:aimRoot)
            if spec.kind == .nova || spec.kind == .heal || spec.kind == .shield || spec.kind == .cyclone {return}
            if spec.kind == .meteor {let aim=(game.aim ?? p.facing);let center=aim.normalized*min(spec.range,max(2,aim.length*spec.range));let marker=SCNNode();marker.position=SCNVector3(Float(center.x),0.05,Float(-center.y));_=ring(3.8,color:Self.blue,parent:marker);aimRoot.addChildNode(marker)}else{_=line(.zero,d*spec.range,width:0.16,color:Self.blue,parent:aimRoot,height:0.1)}
        }else if game.attacking{_=ring(p.range,color:Self.blue.withAlphaComponent(0.40),parent:aimRoot)}
        if p.recall>0{_=ring(1.5+0.4*sin(game.time*5),color:Self.blue,parent:aimRoot)}
    }
    func setQuality(_ high:Bool){highQuality=high;sun.light?.castsShadow=high;camera.camera?.bloomIntensity=high ? 0.18:0}
    static func portraitScene(hero:Int)->SCNScene {
        let r=ArenaRenderer();r.world.removeFromParentNode();r.actors.childNodes.forEach{$0.removeFromParentNode()};let model=r.makeHero(Roster.heroes[hero],team:0,preview:true);model.eulerAngles.y = -.pi/7;r.actors.addChildNode(model);r.scene.background.contents=UIColor(rgb:0x13252F);r.camera.position=SCNVector3(0,2.1,5.6);r.camera.look(at:SCNVector3(0,1.4,0));r.camera.camera?.fieldOfView=37;r.scene.fogStartDistance=100;return r.scene
    }
}
