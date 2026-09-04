import SwiftUI
import SceneKit
import UIKit

@main struct AetherRiftApp:App {var body:some Scene {WindowGroup {ArenaRoot().preferredColorScheme(.dark)}}}
@MainActor final class BattleSession:NSObject,ObservableObject {
    let game:ArenaSimulation;let renderer=ArenaRenderer();@Published var revision=0;@Published var finished=false;var display:CADisplayLink?;var lastTime:CFTimeInterval=0;var hudTime:Double=0;var recorded=false
    init(hero:Int,difficulty:Difficulty,spell:BattleSpell,practice:Bool){game=ArenaSimulation(hero:hero,difficulty:difficulty,spell:spell,practice:practice);super.init();renderer.cameraPoint=game.player.p
        if ProcessInfo.processInfo.arguments.contains("--smoke-battle") {game.player.p=V2(42,42);game.player.hp=game.player.maxHP;game.spawnWave();for h in game.heroes where h.id != game.playerID {h.p=h.team==0 ? V2(43+Double(h.id%3),44+Double(h.id%3)):V2(52+Double(h.id%3),51+Double(h.id%3));game.gain(h,xp:1800,gold:2000)}}
    }
    func start(){guard display==nil else{return};UIApplication.shared.isIdleTimerDisabled=true;lastTime=0;let link=CADisplayLink(target:self,selector:#selector(frame(_:)));link.preferredFramesPerSecond=60;link.add(to:.main,forMode:.common);display=link;ArenaAudio.shared.start()}
    func stop(){display?.invalidate();display=nil;UIApplication.shared.isIdleTimerDisabled=false;ArenaAudio.shared.stop()}
    @objc func frame(_ link:CADisplayLink){let dt=lastTime==0 ? 1.0/60:min(0.05,link.timestamp-lastTime);lastTime=link.timestamp;game.step(dt);renderer.update(game,dt:dt)
        let cues=game.sounds;game.sounds=[];for sound in cues {ArenaAudio.shared.play(sound)};hudTime+=dt;if hudTime>0.10{revision+=1;hudTime=0}
        if game.winner != nil && !recorded {recorded=true;finished=true;revision+=1;if !game.practice{UserDefaults.standard.set(UserDefaults.standard.integer(forKey:"matches")+1,forKey:"matches");if game.winner==0{UserDefaults.standard.set(UserDefaults.standard.integer(forKey:"wins")+1,forKey:"wins")}}}
    }
    func pause(_ value:Bool){game.paused=value;game.movement = .zero;game.attacking=false;game.aimingSkill=nil;lastTime=0;if value{ArenaAudio.shared.stop()}else{ArenaAudio.shared.start()};revision+=1}
}
struct BattlefieldView:UIViewRepresentable {
    let session:BattleSession
    func makeUIView(context:Context)->SCNView{let view=SCNView();view.scene=session.renderer.scene;view.pointOfView=session.renderer.camera;view.backgroundColor=UIColor(rgb:0x263F37);view.antialiasingMode = .multisampling2X;view.preferredFramesPerSecond=60;view.isPlaying=true;view.autoenablesDefaultLighting=false;view.accessibilityIdentifier="battlefield";return view}
    func updateUIView(_ uiView:SCNView,context:Context){}
}
struct HeroPreview:UIViewRepresentable {
    let hero:Int
    func makeUIView(context:Context)->SCNView{let v=SCNView();v.backgroundColor = .clear;v.antialiasingMode = .multisampling4X;v.allowsCameraControl=true;v.autoenablesDefaultLighting=false;return v}
    func updateUIView(_ view:SCNView,context:Context){if view.tag != hero+100{view.scene=ArenaRenderer.portraitScene(hero:hero);view.tag=hero+100}}
}
private let ink=Color(red:0.035,green:0.075,blue:0.11)
private let gold=Color(red:0.86,green:0.72,blue:0.45)
private let cyan=Color(red:0.32,green:0.81,blue:0.96)
extension View {func panel()->some View{self.background(ink.opacity(0.94),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(gold.opacity(0.27),lineWidth:1))}}
struct ArenaRoot:View {
    @State var hero=4;@State var role:Role?;@State var difficulty:Difficulty = .standard;@State var spell:BattleSpell = .flicker;@State var practice=false;@State var match:BattleSession?;@State var help=false
    var body:some View{
        ZStack {ink.ignoresSafeArea();if let session=match {ArenaMatch(session:session){session.stop();match=nil}}
            else {GeometryReader{geo in
                let s=min(geo.size.width/932,geo.size.height/430)
                ZStack {
                    LinearGradient(colors:[Color(red:0.07,green:0.16,blue:0.20),ink],startPoint:.topLeading,endPoint:.bottomTrailing)
                    HStack(spacing:0){
                        VStack(alignment:.leading,spacing:14){
                            Text("REY VICTOR MENDILLO").font(.system(size:8,weight:.semibold)).tracking(3).foregroundColor(gold)
                            Text("AETHER RIFT").font(.system(size:27,weight:.black,design:.serif)).tracking(4).lineSpacing(-2)
                            Text("CHOOSE YOUR CHAMPION").font(.system(size:9,weight:.bold)).tracking(1.5).foregroundColor(.white.opacity(0.55))
                            HStack(spacing:5){roleChip(nil);ForEach(Role.allCases,id:\.self){roleChip($0)}}
                            ScrollView {LazyVGrid(columns:[GridItem(.fixed(95)),GridItem(.fixed(95)),GridItem(.fixed(95))],spacing:7){ForEach(Roster.heroes.filter{role == nil || $0.role==role}){h in Button{hero=h.id;ArenaAudio.shared.play("select")}label:{VStack(spacing:4){Image(systemName:h.role.icon).font(.system(size:20)).foregroundColor(Color(UIColor(rgb:h.color)));Text(h.name).font(.system(size:11,weight:.bold));Text(h.role.rawValue).font(.system(size:8)).foregroundColor(.white.opacity(0.5))}.frame(width:92,height:64).background(hero==h.id ? Color(UIColor(rgb:h.color)).opacity(0.18):.white.opacity(0.035),in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(hero==h.id ? gold:.white.opacity(0.10),lineWidth:1))}.buttonStyle(.plain).accessibilityIdentifier("hero-\(h.id)")}}}.frame(height:216)
                            HStack{Text("OFFLINE 5v5 • NATIVE 3D").font(.system(size:8,weight:.bold)).foregroundColor(cyan);Spacer();Button{help=true}label:{Image(systemName:"questionmark.circle")}.accessibilityIdentifier("guide")}
                        }.frame(width:312).padding(.leading,50).padding(.vertical,18)
                        HeroPreview(hero:hero).frame(width:250,height:390).mask(LinearGradient(colors:[.white,.white,.clear],startPoint:.top,endPoint:.bottom))
                        VStack(alignment:.leading,spacing:9){
                            Text(Roster.heroes[hero].role.rawValue.uppercased()).font(.system(size:9,weight:.bold)).tracking(2).foregroundColor(gold)
                            Text(Roster.heroes[hero].name).font(.system(size:31,weight:.bold,design:.serif))
                            Text(Roster.heroes[hero].title).font(.system(size:11)).foregroundColor(.white.opacity(0.55))
                            Text("PASSIVE · "+Roster.heroes[hero].passive).font(.system(size:9)).foregroundColor(cyan).fixedSize(horizontal:false,vertical:true)
                            ForEach(0..<3){i in let a=Roster.heroes[hero].abilities[i];HStack(alignment:.top,spacing:7){Image(systemName:a.icon).frame(width:22).foregroundColor(gold);VStack(alignment:.leading,spacing:2){Text(a.name).font(.system(size:10,weight:.bold));Text(a.detail).font(.system(size:8)).foregroundColor(.white.opacity(0.5))}}}
                            HStack{Text("AI").font(.system(size:9,weight:.bold));Picker("Difficulty",selection:$difficulty){ForEach(Difficulty.allCases,id:\.self){Text($0.rawValue).tag($0)}}.tint(gold);Spacer();Toggle("Practice",isOn:$practice).font(.system(size:9)).toggleStyle(.switch).scaleEffect(0.8)}
                            HStack(spacing:5){ForEach(BattleSpell.allCases,id:\.self){item in Button{spell=item}label:{VStack(spacing:3){Image(systemName:item.icon);Text(item.rawValue).font(.system(size:7))}.frame(width:56,height:38).foregroundColor(spell==item ? gold:.white.opacity(0.5)).background(.white.opacity(spell==item ? 0.10:0.03),in:RoundedRectangle(cornerRadius:6))}.buttonStyle(.plain)}}
                            Button{match=BattleSession(hero:hero,difficulty:difficulty,spell:spell,practice:practice)}label:{HStack{Text("ENTER THE RIFT").tracking(1.2);Image(systemName:"arrow.right")}.font(.system(size:12,weight:.black)).frame(maxWidth:.infinity).frame(height:43).background(LinearGradient(colors:[gold,Color(red:0.65,green:0.46,blue:0.23)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:8)).foregroundColor(ink)}.buttonStyle(.plain).accessibilityIdentifier("start-match")
                        }.frame(width:255).padding(.trailing,40)
                    }
                }.frame(width:932,height:430).scaleEffect(s).frame(width:geo.size.width,height:geo.size.height)
            }.ignoresSafeArea()}
        }.ignoresSafeArea().statusBarHidden().sheet(isPresented:$help){GuideView()}
        .onAppear{if ProcessInfo.processInfo.arguments.contains("--smoke-battle"){match=BattleSession(hero:4,difficulty:.standard,spell:.flicker,practice:false)}}
    }
    func roleChip(_ r:Role?)->some View {Button{role=r}label:{Image(systemName:r?.icon ?? "square.grid.2x2.fill").font(.system(size:11)).frame(width:36,height:28).background(role==r ? gold.opacity(0.25):.white.opacity(0.04),in:RoundedRectangle(cornerRadius:5)).foregroundColor(role==r ? gold:.white.opacity(0.55))}.buttonStyle(.plain)}
}
struct ArenaMatch:View {
    @ObservedObject var session:BattleSession;let exit:()->Void;@Environment(\.scenePhase)var scenePhase
    @State var shop=false;@State var scoreboard=false;@State var settings=false;@State var quality=true;@State var audio=true;@State var controlHelp=false
    var g:ArenaSimulation{session.game}
    var body:some View {
        ZStack {
            BattlefieldView(session:session).ignoresSafeArea()
            GeometryReader{geo in let s=min(geo.size.width/932,geo.size.height/430)
                ZStack {
                    MiniMap(game:g,onPan:{session.renderer.panPoint=$0},onPing:{g.ping($0)}).frame(width:140,height:140).position(x:113,y:96)
                    HStack(spacing:12){Text("\(g.heroes.filter{$0.team==0}.reduce(0){$0+$1.kills})").foregroundColor(cyan);Text(String(format:"%02d:%02d",Int(g.time)/60,Int(g.time)%60)).font(.system(size:13,weight:.medium,design:.monospaced));Text("\(g.heroes.filter{$0.team==1}.reduce(0){$0+$1.kills})").foregroundColor(.pink)}.font(.system(size:20,weight:.bold)).padding(.horizontal,22).padding(.vertical,5).panel().position(x:466,y:24)
                    Button{scoreboard=true}label:{HStack(spacing:7){Image(systemName:"list.bullet.rectangle");Text("\(g.player.kills) / \(g.player.deaths) / \(g.player.assists)").monospacedDigit()}.font(.system(size:11,weight:.bold)).padding(8).panel()}.buttonStyle(.plain).position(x:696,y:25)
                    Button{settings=true;session.pause(true)}label:{Image(systemName:"gearshape.fill").frame(width:33,height:30).panel()}.buttonStyle(.plain).position(x:880,y:25)
                    Button{shop=true}label:{VStack(spacing:3){HStack{Image(systemName:"bag.fill");Text("\(Int(g.player.gold))").monospacedDigit()}.font(.system(size:16,weight:.bold));Text("EQUIPMENT").font(.system(size:7,weight:.bold)).tracking(1)}.foregroundColor(gold).frame(width:102,height:48).panel()}.buttonStyle(.plain).position(x:843,y:81).accessibilityIdentifier("shop")
                    if let item=g.recommended(for:g.player),g.player.gold>=Double(g.price(item,for:g.player)){Button{_=g.buy(item.id,for:g.player)}label:{HStack(spacing:5){Image(systemName:item.icon).foregroundColor(gold);VStack(alignment:.leading){Text(item.name).font(.system(size:8,weight:.bold));Text("Buy · \(g.price(item,for:g.player))").font(.system(size:8)).foregroundColor(gold)}}.padding(7).panel()}.buttonStyle(.plain).position(x:831,y:130)}
                    if g.time<8{Text("Protect your lanes. Destroy the enemy Nexus.").font(.system(size:13,weight:.semibold)).padding(12).panel().position(x:466,y:83)}
                    else if g.messageUntil>g.time{Text(g.message).font(.system(size:12,weight:.bold)).foregroundColor(gold).padding(9).panel().position(x:466,y:77)}
                    VStack(alignment:.leading,spacing:4){ForEach(g.events.prefix(3)){event in if g.time-event.time<9 {Text(event.text).font(.system(size:8,weight:.semibold)).foregroundColor(event.team==0 ? cyan:.pink)}}}.frame(width:220,alignment:.leading).position(x:305,y:116)
                    HStack(spacing:6){ForEach(0..<3){i in Button{g.ping(g.player.p+g.player.facing*8,mode:i)}label:{Image(systemName:["scope","arrow.uturn.backward","person.3.fill"][i]).font(.system(size:11)).frame(width:28,height:26).panel()}.buttonStyle(.plain)}}.position(x:108,y:185)
                    Text(objectiveText).font(.system(size:8,weight:.medium,design:.monospaced)).foregroundColor(.white.opacity(0.75)).padding(5).panel().position(x:120,y:214)
                    AnalogStick{v in g.movement=v;if v.length>0.05{g.player.recall=0}}.position(x:110,y:333)
                    VStack(spacing:4){HStack{Text("LV \(g.player.level)").foregroundColor(gold);Text(g.player.name);Spacer();Text("\(Int(max(0,g.player.hp))) / \(Int(g.player.maxHP))").monospacedDigit()}.font(.system(size:9,weight:.bold));meter(g.player.hp/g.player.maxHP,Color.green,height:6);meter(g.player.mana/g.player.maxMana,cyan,height:3);meter(g.player.level==15 ? 1:g.player.xp/Double(100+g.player.level*65),gold,height:2)}.frame(width:238).padding(8).panel().position(x:450,y:359)
                    HStack(spacing:5){ForEach(0..<6){i in ZStack{RoundedRectangle(cornerRadius:5).fill(ink.opacity(0.85)).overlay(RoundedRectangle(cornerRadius:5).stroke(gold.opacity(0.2)));if i<g.player.items.count{Image(systemName:Armory.items[g.player.items[i]].icon).foregroundColor(gold)}}.frame(width:26,height:24)}}.position(x:452,y:403)
                    roundAction("Recall","arrow.down.to.line",g.player.recall>0 ? g.player.recall:0,color:cyan){g.recallPlayer()}.position(x:250,y:364)
                    roundAction("Regen","cross.fill",g.player.regenCD,color:.green){g.regenPlayer()}.position(x:313,y:405)
                    roundAction(g.player.spell.rawValue,g.player.spell.icon,g.player.spellCD,color:.orange){g.castSpell(g.player)}.position(x:650,y:363)
                    ForEach(0..<3){i in let points=[CGPoint(x:722,y:345),CGPoint(x:769,y:272),CGPoint(x:850,y:240)];AbilityControl(session:session,index:i).position(points[i])}
                    attackControl("scope",mode:0,size:78).position(x:842,y:345)
                    attackControl("square.stack.3d.up.fill",mode:1,size:39).position(x:767,y:400)
                    attackControl("building.2.fill",mode:2,size:39).position(x:889,y:281)
                    if g.aimingSkill != nil{Text("Drag to aim · release to cast · drag far to cancel").font(.system(size:10,weight:.bold)).padding(9).panel().position(x:467,y:296)}
                    if !g.player.alive {VStack(spacing:7){Text("RETURNING IN \(Int(ceil(g.player.respawn)))").font(.system(size:22,weight:.black));Text("Drag the minimap to watch your teammates").font(.system(size:11))}.padding(22).panel().position(x:466,y:215)}
                    if g.player.recall>0 {Text("Recalling… \(Int(ceil(g.player.recall)))").font(.system(size:13,weight:.bold)).foregroundColor(cyan).position(x:465,y:302)}
                }.frame(width:932,height:430).scaleEffect(s).frame(width:geo.size.width,height:geo.size.height)
            }.ignoresSafeArea()
            if session.finished {endPanel}
        }.ignoresSafeArea().onAppear{session.start()}.onDisappear{session.stop()}
        .onChange(of:scenePhase){phase in if phase != .active{session.pause(true)}else if !settings{session.pause(false)}}
        .sheet(isPresented:$shop){ShopView(session:session)}
        .sheet(isPresented:$scoreboard){ScoreboardView(game:g)}
        .sheet(isPresented:$settings,onDismiss:{session.pause(false)}){settingsPanel}
    }
    var objectiveText:String{let s=g.units.first{$0.kind == .sentinel};let c=g.units.first{$0.kind == .colossus};func timer(_ u:ArenaUnit?)->String{guard let u=u else{return "—"};return u.alive ? "ALIVE":u.respawn>900 ? "DONE":String(format:"%d:%02d",Int(u.respawn)/60,Int(u.respawn)%60)};return "SENTINEL \(timer(s))  ·  COLOSSUS \(timer(c))"}
    func meter(_ value:Double,_ color:Color,height:CGFloat)->some View{GeometryReader{geo in ZStack(alignment:.leading){Capsule().fill(.black.opacity(0.5));Capsule().fill(color).frame(width:geo.size.width*max(0,min(1,value)))}}.frame(height:height)}
    func roundAction(_ title:String,_ icon:String,_ cd:Double,color:Color,action:@escaping()->Void)->some View{Button(action:action){VStack(spacing:3){ZStack{Circle().fill(ink.opacity(0.86)).overlay(Circle().stroke(color.opacity(0.65),lineWidth:1));Image(systemName:icon).font(.system(size:18)).foregroundColor(color).opacity(cd>0 ? 0.3:1);if cd>0{Text("\(Int(ceil(cd)))").font(.system(size:14,weight:.bold,design:.monospaced))}}.frame(width:42,height:42);Text(title).font(.system(size:8,weight:.medium))}}.buttonStyle(.plain)}
    func attackControl(_ icon:String,mode:Int,size:CGFloat)->some View {
        ZStack{Circle().fill(RadialGradient(colors:[Color(red:0.27,green:0.34,blue:0.35),ink],center:.center,startRadius:0,endRadius:size/2)).overlay(Circle().stroke(mode==0 ? gold:.white.opacity(0.4),lineWidth:mode==0 ? 2:1));Image(systemName:icon).font(.system(size:mode==0 ? 28:15,weight:.semibold)).foregroundColor(mode==0 ? gold:.white)}.frame(width:size,height:size).contentShape(Circle()).gesture(DragGesture(minimumDistance:0).onChanged{_ in g.attackMode=mode;g.attacking=true;g.player.recall=0}.onEnded{_ in g.attacking=false}).accessibilityLabel(mode==0 ? "Attack":mode==1 ? "Attack minions":"Attack turret").accessibilityIdentifier(mode==0 ? "attack":"attack-\(mode)")
    }
    var settingsPanel:some View{NavigationStack{Form{Section("Match"){Toggle("Sound and music",isOn:$audio).onChange(of:audio){v in ArenaAudio.shared.enabled=v;if !v{ArenaAudio.shared.stop()}};Toggle("Shadows and bloom",isOn:$quality).onChange(of:quality){session.renderer.setQuality($0)};Text("The match pauses while settings are open.");Button("Controls and rules"){controlHelp=true};if g.practice{Button("Restore health, mana and cooldowns"){g.player.hp=g.player.maxHP;g.player.mana=g.player.maxMana;g.player.cooldowns=[0,0,0];g.player.spellCD=0};Button("Add 5,000 gold"){g.player.gold+=5000}}};Section{Button("Leave match",role:.destructive){settings=false;exit()}}}.navigationTitle("Settings").toolbar{ToolbarItem(placement:.confirmationAction){Button("Resume"){settings=false}}}.sheet(isPresented:$controlHelp){GuideView()}}}
    var endPanel:some View{ZStack{Color.black.opacity(0.74);VStack(spacing:12){Text(g.winner==0 ? "VICTORY":"DEFEAT").font(.system(size:40,weight:.black,design:.serif)).tracking(5).foregroundColor(g.winner==0 ? gold:.pink);Text(g.winner==0 ? "The enemy Nexus has fallen":"Your Nexus has fallen").font(.subheadline).foregroundColor(.white.opacity(0.6));HStack(spacing:30){resultStat("K / D / A","\(g.player.kills) / \(g.player.deaths) / \(g.player.assists)");resultStat("DAMAGE","\(Int(g.player.dealt))");resultStat("GOLD","\(Int(g.player.earnedGold))")};Button("View scoreboard"){scoreboard=true}.tint(cyan);Button("RETURN TO HEROES"){exit()}.font(.headline).padding(.horizontal,32).padding(.vertical,12).background(gold,in:Capsule()).foregroundColor(ink)}}.ignoresSafeArea()}
    func resultStat(_ title:String,_ value:String)->some View{VStack{Text(title).font(.caption2).foregroundColor(.gray);Text(value).font(.headline)}}
}
struct AnalogStick:View {
    let changed:(V2)->Void;@State var offset=CGSize.zero
    var body:some View{ZStack{Circle().fill(ink.opacity(0.42)).overlay(Circle().stroke(.white.opacity(0.20),lineWidth:1)).frame(width:114,height:114);Circle().stroke(.white.opacity(0.08),lineWidth:1).frame(width:80,height:80);Circle().fill(LinearGradient(colors:[cyan.opacity(0.48),ink.opacity(0.8)],startPoint:.topLeading,endPoint:.bottomTrailing)).overlay(Circle().stroke(cyan.opacity(0.7),lineWidth:1.5)).frame(width:47,height:47).offset(offset)}.contentShape(Circle()).gesture(DragGesture(minimumDistance:0).onChanged{value in let v=V2(Double(value.translation.width),Double(-value.translation.height));let clamped=v.length>48 ? v.normalized*48:v;offset=CGSize(width:clamped.x,height:-clamped.y);changed(clamped*(1/48))}.onEnded{_ in offset = .zero;changed(.zero)}).accessibilityIdentifier("joystick")}
}
struct AbilityControl:View {
    @ObservedObject var session:BattleSession;let index:Int;@State var cancelled=false;@State var dragged=false
    var u:ArenaUnit{session.game.player};var a:Ability{u.def.abilities[index]}
    var body:some View {
        VStack(spacing:3){ZStack {
            Circle().fill(RadialGradient(colors:[Color(UIColor(rgb:u.def.color)).opacity(0.50),ink.opacity(0.94)],center:.center,startRadius:0,endRadius:36)).overlay(Circle().stroke(cancelled ? .red:index==2 ? gold:cyan.opacity(0.7),lineWidth:2))
            Image(systemName:a.icon).font(.system(size:index==2 ? 26:22,weight:.semibold)).foregroundColor(index==2 ? gold:.white).opacity(u.cooldowns[index]>0 || u.ranks[index]==0 ? 0.25:1)
            if u.cooldowns[index]>0 {Text("\(Int(ceil(u.cooldowns[index])))").font(.system(size:19,weight:.bold,design:.monospaced))}
            if u.ranks[index]==0{Image(systemName:"lock.fill").font(.system(size:13)).foregroundColor(.white)}
        }.frame(width:index==2 ? 61:55,height:index==2 ? 61:55).contentShape(Circle()).gesture(DragGesture(minimumDistance:0).onChanged{value in let delta=V2(Double(value.translation.width),Double(-value.translation.height));dragged=delta.length>8;cancelled=delta.length>140;session.game.aimingSkill=index;session.game.aim=delta.length>5 ? delta*(1/70):u.facing}.onEnded{_ in if !cancelled{session.game.cast(index,by:u,direction:dragged ? session.game.aim:nil)};session.game.aimingSkill=nil;session.game.aim=nil;cancelled=false;dragged=false})
            Text(a.name).font(.system(size:7,weight:.bold)).lineLimit(1).frame(width:84)
            HStack(spacing:2){ForEach(0..<(index==2 ? 3:6)){j in Circle().fill(j<u.ranks[index] ? gold:.white.opacity(0.2)).frame(width:3,height:3)}}
        }.overlay(alignment:.top){if session.game.canLearn(index,for:u){Button{session.game.learn(index,for:u);session.revision+=1}label:{Image(systemName:"plus").font(.system(size:12,weight:.black)).frame(width:27,height:23).background(gold,in:RoundedRectangle(cornerRadius:5)).foregroundColor(ink)}.buttonStyle(.plain).offset(y:-25).accessibilityIdentifier("learn-\(index)")}}.accessibilityIdentifier("skill-\(index)")
    }
}
