import SceneKit
import UIKit

extension UIColor {
    convenience init(rgb:UInt32,alpha:CGFloat=1){self.init(red:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,blue:CGFloat(rgb&255)/255,alpha:alpha)}
}
final class ArenaRenderer {
    let scene=SCNScene();let camera=SCNNode();let world=SCNNode();let actors=SCNNode();let fxRoot=SCNNode();let aimRoot=SCNNode()
    var nodes:[Int:SCNNode]=[:];var fxNodes:[Int:SCNNode]=[:];var cameraPoint=V2(8,8);var panPoint:V2?;var highQuality=true
    private var pet=SCNNode();private var ambient=SCNNode();private var sun=SCNNode();private var aimStamp=""
    private var targetRing:SCNNode?;private var shake:Double=0;private var previousHP:Double?
    static let gold=UIColor(rgb:0xD4B578);static let blue=UIColor(rgb:0x50CEFA);static let red=UIColor(rgb:0xF17980)
    init(preview:Bool=false){
        scene.rootNode.addChildNode(world);scene.rootNode.addChildNode(actors);scene.rootNode.addChildNode(fxRoot);scene.rootNode.addChildNode(aimRoot)
        scene.background.contents=UIColor(rgb:0x192E35);scene.fogColor=UIColor(rgb:0x405D58);scene.fogStartDistance=62;scene.fogEndDistance=125
        camera.camera=SCNCamera();camera.camera?.fieldOfView=44;camera.camera?.zNear=0.3;camera.camera?.zFar=180;camera.camera?.wantsHDR=true;camera.camera?.bloomIntensity=0.12;camera.camera?.bloomThreshold=1.2;camera.camera?.exposureOffset = -0.35;camera.camera?.vignettingIntensity=0.25;camera.camera?.vignettingPower=0.7;scene.rootNode.addChildNode(camera)
        scene.lightingEnvironment.contents=environmentMap();scene.lightingEnvironment.intensity=0.85
        ambient.light=SCNLight();ambient.light?.type = .ambient;ambient.light?.color=UIColor(rgb:0xA4C6D3);ambient.light?.intensity=160;scene.rootNode.addChildNode(ambient)
        sun.light=SCNLight();sun.light?.type = .directional;sun.light?.color=UIColor(rgb:0xFFE4BE);sun.light?.intensity=1150;sun.light?.castsShadow=true;sun.light?.shadowMode = .deferred;sun.light?.shadowColor=UIColor.black.withAlphaComponent(0.35);sun.light?.shadowMapSize=CGSize(width:2048,height:2048);sun.light?.orthographicScale=60;sun.light?.maximumShadowDistance=70;sun.eulerAngles=SCNVector3(-Float.pi/3,-Float.pi/5,0);scene.rootNode.addChildNode(sun)
        sun.light?.intensity=850;sun.light?.shadowRadius=3
        if !preview {buildTerrain();pet=makePet();actors.addChildNode(pet);let marker=ring(1.05,color:Self.gold,parent:fxRoot);marker.name="targetRing";marker.isHidden=true;targetRing=marker}
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
        let d=b-a;let n=box(CGFloat(width),0.025,CGFloat(d.length),color,SCNVector3(Float((a.x+b.x)/2),height,Float(-(a.y+b.y)/2)),parent,bevel:0);n.eulerAngles.y=Float(atan2(d.x,-d.y));return n
    }
    func terrainTexture()->UIImage {
        let size=CGSize(width:512,height:512);return UIGraphicsImageRenderer(size:size).image{ctx in
            UIColor(rgb:0x395B3F).setFill();ctx.fill(CGRect(origin:.zero,size:size));var seed:UInt64=42
            for _ in 0..<20000 {seed=seed &* 1664525 &+ 1013904223;let x=CGFloat(seed%512);seed=seed &* 1664525 &+ 1013904223;let y=CGFloat(seed%512);let tone=CGFloat(seed%55)/255;UIColor(red:0.17+tone,green:0.27+tone,blue:0.17+tone*0.7,alpha:0.45).setFill();ctx.fill(CGRect(x:x,y:y,width:CGFloat(seed%3+1),height:CGFloat(seed%4+1)))}
        }
    }
    func buildTerrain(){buildEnchantedTerrain()}
    func segmentDistance(_ p:V2,_ a:V2,_ b:V2)->Double{let d=b-a;let t=max(0,min(1,(p-a).dot(d)/max(0.001,d.dot(d))));return p.distance(a+d*t)}
    func makeTree(_ p:V2,scale:Double,parent:SCNNode){
        let root=SCNNode();root.position=SCNVector3(Float(p.x),0,Float(-p.y));root.scale=SCNVector3(Float(scale),Float(scale),Float(scale))
        _=cylinder(0.28,3,UIColor(rgb:0x695B45),SCNVector3(0,1.5,0),root)
        for i in 0..<4 {_=sphere(1.6,UIColor(rgb:i%2==0 ? 0x426F4A:0x527E50),SCNVector3(Float(i%2)*1.1-0.5,3+Float(i%3)*0.5,Float(i/2)*0.8-0.4),root,scale:SCNVector3(1,0.85,1))};parent.addChildNode(root)
    }
    func makeHero(_ def:HeroDef,team:Int,preview:Bool=false)->SCNNode {sculptHero(def,team:team,preview:preview)}
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
            let crystal=jewel(u.kind == .core ? 1.45:0.70,color:color,at:SCNVector3(0,u.kind == .core ? 4.0:3.3,0),in:root);crystal.name="crystal"
            let range=ring(u.range,color:color.withAlphaComponent(0.5),parent:root);range.name="dangerRange";range.isHidden=true
            for i in 0..<4 {let a=Float(i) * .pi/2;let buttress=mesh(sculpt([(0,0.28,0.32),(0.5,0.24,0.28),(2.0,0.13,0.17)],sides:6),stone,SCNVector3(cos(a)*1.0,0,sin(a)*1.0),root);buttress.eulerAngles.y = -a}
            let orbit=ring(u.kind == .core ? 1.9:0.95,color:Self.gold,parent:root,height:u.kind == .core ? 3.4:2.95);orbit.opacity=0.6
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
        let hud=SCNNode();hud.name="health";hud.position=SCNVector3(0,u.isHero ? 3.32:u.structure ? 6.0:u.neutral || u.kind == .summoned ? 4.5:1.7,0)
        let billboard=SCNBillboardConstraint();billboard.freeAxes = .all;hud.constraints=[billboard]
        let width:CGFloat=u.structure ? 3:u.isHero ? 2.0:1.25
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
            if !u.structure {let rotation=Float(atan2(u.facing.x,-u.facing.y));let difference=atan2(sin(rotation-n.eulerAngles.y),cos(rotation-n.eulerAngles.y));n.eulerAngles.y += difference*Float(min(1,dt*16))}
            let moving=u.p.distance(u.lastPosition)>0.005;let stride=Float(sin(game.time*11+Double(u.id)))*(moving ? 0.5:0.015)
            if let body=n.childNode(withName:"body",recursively:false),!n.isHidden {
                let swing=Float(sin(min(1,u.attackPose/0.27) * .pi));body.position.y=moving ? abs(stride)*0.08:Float(sin(game.time*2+Double(u.id)))*0.016
                body.eulerAngles.y=u.cycloning>0 ? Float(game.time*16):swing*0.25
                body.childNode(withName:"legL",recursively:false)?.eulerAngles.x=stride;body.childNode(withName:"legR",recursively:false)?.eulerAngles.x = -stride
                body.childNode(withName:"legL",recursively:false)?.childNode(withName:"shin",recursively:false)?.eulerAngles.x=max(0,-stride)*0.7
                body.childNode(withName:"legR",recursively:false)?.childNode(withName:"shin",recursively:false)?.eulerAngles.x=max(0,stride)*0.7
                body.childNode(withName:"armL",recursively:false)?.eulerAngles.x=u.range>5 && u.attackPose>0 ? -0.9:-stride*0.55
                body.childNode(withName:"armR",recursively:false)?.eulerAngles.x=u.attackPose>0 ? -0.30-swing*1.5:stride*0.55
                body.childNode(withName:"cape",recursively:false)?.eulerAngles.x=moving ? 0.12:0
            }
            if let bar=n.childNode(withName:"fill",recursively:true){bar.scale.x=Float(max(0,u.hp/u.maxHP))}
            if let crystal=n.childNode(withName:"crystal",recursively:false){crystal.eulerAngles.y=Float(game.time*0.4);crystal.position.y=(u.kind == .core ? 4.0:3.3)+Float(sin(game.time*2))*0.13}
            if let danger=n.childNode(withName:"dangerRange",recursively:false) {danger.isHidden = !u.alive || u.team==0 || u.p.distance(game.player.p)>u.range+4;danger.opacity=u.target==game.playerID ? 0.9:0.30}
            let shield=n.childNode(withName:"shieldBubble",recursively:false)
            if u.shield>0 {if shield==nil {let s=sphere(1.1,Self.blue.withAlphaComponent(0.15),SCNVector3(0,1.15,0),n,scale:SCNVector3(1,1.25,1),glow:true);s.name="shieldBubble";s.geometry?.firstMaterial?.transparency=0.20}}else{shield?.removeFromParentNode()}
            if u.id==game.playerID {n.opacity=u.conceal>0 || Battlefield.inBrush(u.p) != nil ? 0.62:1}
            if let hp=n.childNode(withName:"health",recursively:false){hp.opacity=game.time-u.attackedAt<0.13 ? 0.5:1}
        }
        let desired=panPoint ?? game.player.p;let target=Battlefield.clamp(desired);cameraPoint=cameraPoint+(target-cameraPoint)*min(1,dt*8)
        if let hp=previousHP,hp-game.player.hp>80{shake=min(0.13,(hp-game.player.hp)/3000)};previousHP=game.player.hp;shake=max(0,shake-dt*0.45)
        camera.position=SCNVector3(Float(cameraPoint.x+sin(game.time*61)*shake),25.5,Float(-cameraPoint.y)+18.5);camera.look(at:SCNVector3(Float(cameraPoint.x),0,Float(-cameraPoint.y)))
        if let selected=game.selectedTarget.flatMap({game.unit($0)}),selected.alive,game.visible(selected,to:0) {targetRing?.isHidden=false;targetRing?.position=SCNVector3(Float(selected.p.x),0.10,Float(-selected.p.y));let s=Float(1+sin(game.time*5)*0.04);targetRing?.scale=SCNVector3(s,1,s)}else{targetRing?.isHidden=true}
        pet.isHidden = !game.player.alive;let petTarget=game.player.p+V2(-1.5,-1.6);pet.position=SCNVector3(Float(petTarget.x),Float(sin(game.time*5))*0.05,Float(-petTarget.y));pet.eulerAngles.y=Float(atan2(game.player.facing.x,-game.player.facing.y))
        updateEffects(game);updateAim(game)
    }
    func updateEffects(_ game:ArenaSimulation){
        let ids=Set(game.effects.map(\.id));for id in Array(fxNodes.keys) where !ids.contains(id){fxNodes[id]?.removeFromParentNode();fxNodes.removeValue(forKey:id)}
        for f in game.effects where f.a.distance(cameraPoint)<34 {
            let root:SCNNode
            if let n=fxNodes[f.id]{root=n}else{
                root=SCNNode();root.position=SCNVector3(Float(f.a.x),0.2,Float(-f.a.y));let c=f.team==0 ? Self.blue:f.team==1 ? Self.red:Self.gold
                switch f.kind {
                case "damage":
                    // Only render local combat numbers, keeping distant battles inexpensive.
                    if f.a.distance(game.player.p)<18 {let text=SCNText(string:String(Int(f.value)),extrusionDepth:0);text.font=UIFont.systemFont(ofSize:0.42,weight:.bold);text.flatness=0.3;text.firstMaterial=material(f.team==0 ? Self.gold:Self.red);text.firstMaterial?.lightingModel = .constant;let n=SCNNode(geometry:text);n.constraints=[SCNBillboardConstraint()];n.position=SCNVector3(-0.25,2.3,0);root.addChildNode(n)}
                case "projectile":_=sphere(f.value>0 ? 0.18:0.10,c,SCNVector3(0,1.1,0),root,glow:true);_=line(.zero,f.b-f.a,width:f.value>0 ? 0.10:0.04,color:c,parent:root,height:1.1)
                case "meteor":_=sphere(1,c,SCNVector3(0,0.3,0),root,scale:SCNVector3(Float(f.value),0.35,Float(f.value)),glow:true);_=ring(f.value,color:c,parent:root)
                case "warning":_=ring(f.value,color:Self.red,parent:root)
                case "heal":_=ring(1.2,color:UIColor.systemGreen,parent:root);sparks(color:.systemGreen,parent:root,count:8)
                case "slash","critical","cone":let end=f.b-f.a;let arc=mesh(SCNTorus(ringRadius:CGFloat(f.kind=="cone" ? min(4,f.value):1.2),pipeRadius:0.065),c,SCNVector3(0,0.8,0),root,glow:true);arc.scale=SCNVector3(1,0.5,0.42);root.eulerAngles.y=Float(atan2(end.x,-end.y));sparks(color:Self.gold,parent:root,count:6)
                case "hook","cast":_=line(.zero,f.b-f.a,width:0.07,color:c,parent:root,height:1.0)
                case "impact","death":sparks(color:c,parent:root,count:f.kind=="death" ? 12:5)
                default:_=ring(f.value>0 ? min(7,f.value):2,color:c,parent:root)
                }
                fxRoot.addChildNode(root);fxNodes[f.id]=root
            }
            let progress=Float(1-f.ttl/f.duration);root.opacity=CGFloat(1-progress);if f.kind=="damage"{root.position.y=0.2+progress*1.5}else if f.kind != "projectile" && f.kind != "warning" {let s=0.6+progress*0.7;root.scale=SCNVector3(s,s,s)}
            for spark in root.childNodes where spark.name=="spark" {spark.position.y=0.5+progress*2;let scale=Float(1-progress);spark.scale=SCNVector3(scale,scale,scale)}
        }
    }
    func updateAim(_ game:ArenaSimulation){
        let p=game.player;aimRoot.isHidden = !p.alive;guard p.alive else{return}
        aimRoot.position=SCNVector3(Float(p.p.x),0.14,Float(-p.p.y))
        let direction=game.aim ?? p.facing
        let stamp="\(game.aimingSkill ?? -1)-\(game.attacking)-\(Int(direction.x*50))-\(Int(direction.y*50))-\(p.recall>0)-\(p.range)"
        guard stamp != aimStamp else{return};aimStamp=stamp;aimRoot.childNodes.forEach{$0.removeFromParentNode()}
        if let i=game.aimingSkill {let spec=p.def.abilities[i];let d=(game.aim ?? p.facing).normalized
            _=ring(spec.range,color:Self.blue.withAlphaComponent(0.40),parent:aimRoot)
            if spec.kind == .nova || spec.kind == .heal || spec.kind == .shield || spec.kind == .cyclone {return}
            if spec.kind == .meteor {let aim=(game.aim ?? p.facing);let center=aim.normalized*min(spec.range,max(2,aim.length*spec.range));let marker=SCNNode();marker.position=SCNVector3(Float(center.x),0.05,Float(-center.y));_=ring(3.8,color:Self.blue,parent:marker);aimRoot.addChildNode(marker)}else{_=line(.zero,d*spec.range,width:0.16,color:Self.blue,parent:aimRoot,height:0.1)}
        }else if game.attacking{_=ring(p.range,color:Self.blue.withAlphaComponent(0.40),parent:aimRoot)}
        if p.recall>0{_=ring(1.8,color:Self.blue,parent:aimRoot);let column=cylinder(1.6,4,Self.blue.withAlphaComponent(0.08),SCNVector3(0,2,0),aimRoot,glow:true);column.geometry?.firstMaterial?.transparency=0.15}
    }
    func sparks(color:UIColor,parent:SCNNode,count:Int){for i in 0..<count{let a=Float(i)*2.4,r=Float(i%4+1)*0.25;let n=jewel(0.07,color:color,at:SCNVector3(cos(a)*r,0.5,sin(a)*r),in:parent);n.name="spark"}}
    func setQuality(_ high:Bool){highQuality=high;sun.light?.castsShadow=high;camera.camera?.bloomIntensity=high ? 0.18:0}
    static func portraitScene(hero:Int)->SCNScene {
        let r=ArenaRenderer(preview:true);let model=r.makeHero(Roster.heroes[hero],team:0,preview:true);model.eulerAngles.y = -.pi/8;r.actors.addChildNode(model)
        r.scene.background.contents=UIColor.clear;r.camera.position=SCNVector3(0,2.0,6.4);r.camera.look(at:SCNVector3(0,1.75,0));r.camera.camera?.fieldOfView=35;r.camera.camera?.exposureOffset = -0.05;r.scene.fogStartDistance=100
        let floor=r.cylinder(1.25,0.16,UIColor(rgb:0x203B43),SCNVector3(0,-0.08,0),r.world);_=r.ring(1.15,color:Self.gold.withAlphaComponent(0.65),parent:floor,height:0.10)
        let rim=SCNNode();rim.light=SCNLight();rim.light?.type = .omni;rim.light?.color=UIColor(rgb:Roster.heroes[hero].color);rim.light?.intensity=380;rim.position=SCNVector3(-2,3,-2);r.scene.rootNode.addChildNode(rim)
        model.runAction(.repeatForever(.sequence([.rotateBy(x:0,y:0.10,z:0,duration:3),.rotateBy(x:0,y:-0.10,z:0,duration:3)])))
        return r.scene
    }
}
