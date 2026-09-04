import Foundation

enum UnitKind { case hero, melee, caster, siege, tower, core, camp, sentinel, colossus, summoned }
final class ArenaUnit: Identifiable {
    let id:Int; let kind:UnitKind; var team:Int; var p:V2; var home:V2; var hero:Int; var lane:Int; var tier:Int=0
    var hp:Double; var baseHP:Double; var mana:Double=600; var level=1; var xp:Double=0; var gold:Double=300; var earnedGold:Double=300
    var items:[Int]=[]; var ranks=[1,0,0]; var points=0; var cooldowns=[0.0,0.0,0.0]; var spell:BattleSpell = .flicker; var spellCD:Double=0; var regenCD:Double=0
    var attackTimer:Double=0; var stun:Double=0; var slow:Double=0; var shield:Double=0; var shieldTime:Double=0; var conceal:Double=0; var revealed:Double=0; var speedBuff:Double=0; var hasteBuff:Double=0; var damageBuff:Double=0; var blueBuff:Double=0; var redBuff:Double=0; var immunity:Double=0
    var respawn:Double=0; var attackedAt:Double = -100; var recall:Double=0; var regenerate:Double=0; var facing=V2(0,1); var waypoint=0; var hits=0; var kills=0; var deaths=0; var assists=0; var streak=0; var dealt:Double=0; var healing:Double=0
    var attackers:[Int:Double]=[:]; var target:Int?; var towerShots=0; var aiTimer:Double=0; var aiDestination=V2.zero; var cycloning:Double=0; var cycleTick:Double=0; var attackPose:Double=0; var lastPosition=V2.zero
    init(id:Int,kind:UnitKind,team:Int,p:V2,hp:Double,hero:Int=0,lane:Int=1) { self.id=id; self.kind=kind; self.team=team; self.p=p; self.home=p; self.hp=hp; self.baseHP=hp; self.hero=hero; self.lane=lane; self.lastPosition=p }
    var def:HeroDef { Roster.heroes[hero] }
    var alive:Bool { hp>0 && respawn<=0 }
    var isHero:Bool { kind == .hero }
    var structure:Bool { kind == .tower || kind == .core }
    var neutral:Bool { team == 2 }
    func stat(_ key:KeyPath<Equipment,Double>)->Double {items.reduce(0){$0+Armory.items[$1][keyPath:key]}}
    var maxHP:Double {baseHP+(isHero ? Double(level-1)*175+stat(\.hp):0)}
    var maxMana:Double {600+Double(level-1)*35}
    var attack:Double { isHero ? def.attack+Double(level-1)*9+stat(\.attack) : kind == .tower ? 330 : kind == .core ? 400 : kind == .summoned ? 420 : kind == .colossus ? 200 : kind == .sentinel ? 130 : kind == .camp ? 80 : kind == .siege ? 90 : 55 }
    var armor:Double {isHero ? 18+Double(level)*4+stat(\.armor):structure ? 40 : 12}
    var resist:Double {isHero ? 12+Double(level)*2+stat(\.resist):20}
    var range:Double {isHero ? def.range : structure ? 8.5 : kind == .caster || kind == .siege ? 5.3 : 2.6}
    var speed:Double {(isHero ? def.speed*(1+stat(\.speed)) : kind == .summoned ? 3.5 : neutral ? 3.8 : 4.2)*(slow>0 ? 0.60:1)*(speedBuff>0 ? 1.40:1)}
    var attackInterval:Double {isHero ? max(0.24,0.95/(1+stat(\.attackSpeed)+(hasteBuff>0 ? 0.55:0)+Double(level-1)*0.02)): structure ? 1.15 : 1.3}
    var cdr:Double {min(0.40,stat(\.haste)+(blueBuff>0 ? 0.10:0))}
    var name:String {switch kind {case .hero:return def.name; case .tower:return "Turret";case .core:return "Nexus";case .sentinel:return "Tide Sentinel";case .colossus:return "Rift Colossus";case .camp:return tier == 1 ? "Azure Guardian" : tier == 2 ? "Ember Guardian":"Jungle Beast";case .summoned:return "Allied Colossus";default:return "Minion"}}
}
struct ArenaEvent:Identifiable {let id:Int;let text:String;let team:Int;let time:Double}
struct CombatFX:Identifiable {let id:Int;let kind:String;let a:V2;let b:V2;let team:Int;let value:Double;var ttl:Double;var duration:Double}
struct Missile {let source:Int;var p:V2;let direction:V2;var distance:Double;let speed:Double;let width:Double;let damage:Double;let magic:Bool;let root:Bool;var hit:Set<Int>=[];let homing:Int?}
struct DelayedBlast {let source:Int;let point:V2;var delay:Double;let power:Double}

final class ArenaSimulation {
    var units:[ArenaUnit]=[]; var time:Double=0;var winner:Int?;var playerID=0;var movement=V2.zero;var aim:V2?;var aimingSkill:Int?;var attacking=false;var attackMode=0;var selectedTarget:Int?;var paused=false
    var events:[ArenaEvent]=[];var effects:[CombatFX]=[];var missiles:[Missile]=[];var blasts:[DelayedBlast]=[];var sounds:[String]=[];var message="Welcome to Aether Rift";var messageUntil:Double=5
    var difficulty:Difficulty;var practice:Bool;var autoplay=false;var nextWave:Double=8;var nextIncome:Double=1;var nextID=0;var fxID=0;var eventID=0;var seed:UInt64=1234567;var pingPoint:V2?;var pingUntil:Double=0;var pingMode=0
    init(hero:Int,difficulty:Difficulty = .standard,spell:BattleSpell = .flicker,practice:Bool=false) {
        self.difficulty=difficulty;self.practice=practice
        let p=add(.hero,0,Battlefield.bases[0],Roster.heroes[hero].hp,hero:hero);playerID=p.id;p.spell=spell
        var allies=[0,1,2,3,4];if let index=allies.firstIndex(where:{Roster.heroes[$0].role == p.def.role}) {allies.remove(at:index)}else{allies.removeFirst()}
        for (i,h) in allies.enumerated(){_ = add(.hero,0,V2(7+Double(i)*1.4,10),Roster.heroes[h].hp,hero:h)}
        for (i,h) in [6,7,8,9,10].enumerated(){_ = add(.hero,1,V2(89+Double(i)*1.2,90),Roster.heroes[h].hp,hero:h)}
        for team in 0...1 {
            for lane in 0...2 {
                for (i,t) in [0.18,0.30,0.41].enumerated(){let u=add(.tower,team,Battlefield.point(lane:lane,progress:team == 0 ? t:1-t),3600+Double(2-i)*300,lane:lane);u.tier=3-i}
            }
            _=add(.core,team,Battlefield.bases[team],6800)
        }
        for (i,p) in [V2(24,32),V2(32,17),V2(28,63),V2(68,83),V2(76,68),V2(72,37),V2(42,17),V2(58,83)].enumerated(){let u=add(.camp,2,p,1800);u.tier=i%3;u.respawn=10;u.hp=0}
        let sentinel=add(.sentinel,2,V2(35,65),7500);sentinel.hp=0;sentinel.respawn=practice ? 15:120
        let colossus=add(.colossus,2,V2(65,35),14000);colossus.hp=0;colossus.respawn=practice ? 25:480
        for u in heroes {u.lane=u.def.role.lane;if u.def.role == .assassin {u.spell = .retribution}}
        p.spell=spell
        if practice {p.gold=20000;p.earnedGold=20000;gain(p,xp:30000,gold:0)}
    }
    var player:ArenaUnit {units.first{$0.id==playerID}!}
    var heroes:[ArenaUnit] {units.filter{$0.isHero}}
    func unit(_ id:Int)->ArenaUnit? {units.first{$0.id==id}}
    @discardableResult func add(_ kind:UnitKind,_ team:Int,_ p:V2,_ hp:Double,hero:Int=0,lane:Int=1)->ArenaUnit {
        let u=ArenaUnit(id:nextID,kind:kind,team:team,p:p,hp:hp,hero:hero,lane:lane);nextID+=1;units.append(u);return u
    }
    func random()->Double {seed=seed &* 6364136223846793005 &+ 1;return Double(seed>>32)/Double(UInt32.max)}
    func say(_ text:String,_ team:Int=0) {message=text;messageUntil=time+3.2;eventID+=1;events.insert(ArenaEvent(id:eventID,text:text,team:team,time:time),at:0);if events.count>8{events.removeLast()}}
    func fx(_ kind:String,_ a:V2,_ b:V2,_ team:Int,_ value:Double=0,_ duration:Double=0.4) {fxID+=1;effects.append(CombatFX(id:fxID,kind:kind,a:a,b:b,team:team,value:value,ttl:duration,duration:duration));if effects.count>120{effects.removeFirst(effects.count-120)}}
    func sound(_ s:String){if sounds.count<12{sounds.append(s)}}
    func visible(_ target:ArenaUnit,to team:Int)->Bool {
        if target.team == team || target.structure {return target.alive}
        guard target.alive else{return false}
        let observers=units.filter{$0.team==team && $0.alive && ($0.isHero || $0.structure || !$0.neutral)}
        let brush=Battlefield.inBrush(target.p)
        return observers.contains { observer in
            let d=observer.p.distance(target.p)
            if d > (observer.isHero ? 14:10) {return false}
            if target.revealed>0 || d<2.8 {return true}
            if target.conceal>0{return false}
            return brush == nil || Battlefield.inBrush(observer.p)==brush
        }
    }
    func vulnerable(_ tower:ArenaUnit)->Bool {
        if tower.kind == .core {return (0...2).contains{lane in !units.contains{$0.team==tower.team && $0.kind == .tower && $0.lane==lane && $0.alive}}}
        return !units.contains{$0.kind == .tower && $0.team==tower.team && $0.lane==tower.lane && $0.tier<tower.tier && $0.alive}
    }
    func enemies(of u:ArenaUnit,range:Double,includeNeutral:Bool=true)->[ArenaUnit] {
        units.filter{$0.id != u.id && $0.team != u.team && $0.alive && (includeNeutral || !$0.neutral) && $0.p.distance(u.p)<=range && ($0.neutral || visible($0,to:u.team))}
    }
    func price(_ item:Equipment,for u:ArenaUnit)->Int {item.cost-(item.component.flatMap{u.items.contains($0) ? Armory.items[$0].cost:nil} ?? 0)}
    @discardableResult func buy(_ id:Int,for u:ArenaUnit)->Bool {
        guard Armory.items.indices.contains(id) else{return false};let item=Armory.items[id];let cost=price(item,for:u);let replacement=item.component.flatMap{u.items.firstIndex(of:$0)}
        guard u.gold>=Double(cost),u.items.count<6 || replacement != nil,!u.items.contains(id) else{if u.id==playerID{message="Need gold, a free slot, or an unowned item";messageUntil=time+2};return false}
        // A hero can carry only one pair of boots; an owned component can be upgraded.
        if item.group == .movement && u.items.contains(where:{Armory.items[$0].group == .movement && $0 != item.component}) {return false}
        let before=u.maxHP;if let index=replacement {u.items.remove(at:index)};u.items.append(id);u.gold-=Double(cost);u.hp+=max(0,u.maxHP-before)
        if u.id==playerID{sound("purchase");message="Purchased \(item.name)";messageUntil=time+2};return true
    }
    func sell(_ slot:Int) {guard player.items.indices.contains(slot) else{return};let id=player.items.remove(at:slot);player.gold+=Double(Armory.items[id].cost)*0.60;player.hp=min(player.hp,player.maxHP);sound("purchase")}
    func recommended(for u:ArenaUnit)->Equipment? {Armory.build(for:u.def.role).first(where:{!u.items.contains($0)}).map{Armory.items[$0]}}
    func learn(_ index:Int,for u:ArenaUnit){guard (0...2).contains(index),u.points>0 else{return};let maxRank=index==2 ? 3:6;let needed=index==2 ? 4+u.ranks[index]*4 : u.ranks[index]*2+1;guard u.ranks[index]<maxRank,u.level>=needed else{return};u.ranks[index]+=1;u.points-=1}
    func canLearn(_ index:Int,for u:ArenaUnit)->Bool {u.points>0 && u.ranks[index]<(index==2 ? 3:6) && u.level >= (index==2 ? 4+u.ranks[index]*4:u.ranks[index]*2+1)}
    func autoLearn(_ u:ArenaUnit) {for _ in 0..<15 {let old=u.points;for i in [2,0,1]{learn(i,for:u)};if old==u.points{break}}}
    func gain(_ u:ArenaUnit,xp:Double,gold:Double){guard u.isHero else{return};u.xp+=xp;u.gold+=gold;u.earnedGold+=gold
        while u.level<15 && u.xp>=Double(100+u.level*65){u.xp-=Double(100+u.level*65);u.level+=1;u.points+=1;u.hp=min(u.maxHP,u.hp+175);u.mana=min(u.maxMana,u.mana+35);if u.id==playerID{sound("level");fx("ring",u.p,u.p,u.team,3,0.8)}}
        if u.id != playerID || autoplay {autoLearn(u)}
    }
    func move(_ u:ArenaUnit,direction:V2,dt:Double) {
        guard u.stun<=0,u.alive,direction.length>0.05 else{return};let delta=direction.normalized*u.speed*dt;let next=u.p+delta
        if Battlefield.walkable(next){u.p=next}else if Battlefield.walkable(u.p+V2(delta.x,0)){u.p.x+=delta.x}else if Battlefield.walkable(u.p+V2(0,delta.y)){u.p.y+=delta.y}
        u.facing=direction.normalized
    }
    func walk(_ u:ArenaUnit,to p:V2,dt:Double) {
        let dir=(p-u.p).normalized
        let proposed=u.p+dir*max(1.3,u.speed*dt)
        if !Battlefield.walkable(proposed) {
            for sign in [1.0,-1.0] {let side=V2(dir.x*0.25-dir.y*sign,dir.y*0.25+dir.x*sign).normalized;if Battlefield.walkable(u.p+side*1.4){move(u,direction:side,dt:dt);return}}
        };move(u,direction:dir,dt:dt)
    }
    func blink(_ u:ArenaUnit,dir:V2,distance:Double) {var end=Battlefield.clamp(u.p+dir.normalized*distance);for _ in 0..<20{if Battlefield.walkable(end){break};end=end+(u.p-end)*0.15};if Battlefield.walkable(end){fx("blink",u.p,end,u.team,0,0.4);u.p=end}}
    func recallPlayer(){let p=player;guard p.alive else{return};p.recall=6;movement = .zero;attacking=false;sound("recall")}
    func regenPlayer(){let p=player;guard p.alive,p.regenCD<=0 else{return};p.regenCD=60;p.regenerate=5;sound("heal")}
    func castSpell(_ u:ArenaUnit,dir:V2?=nil) {
        guard u.alive,u.spellCD<=0,(u.stun<=0 || u.spell == .purify) else{return};let d=dir ?? u.facing
        switch u.spell {
        case .flicker:blink(u,dir:d,distance:6)
        case .sprint:u.speedBuff=6;u.slow=0
        case .purify:u.stun=0;u.slow=0;u.immunity=1.5
        case .retribution:guard let t=enemies(of:u,range:7).filter({$0.neutral || $0.kind == .summoned}).min(by:{$0.hp<$1.hp}) else {return};damage(t,amount:600+Double(u.level)*100,source:u,magic:false,trueDamage:true)
        };u.recall=0;u.spellCD=u.spell.cooldown;fx("ring",u.p,u.p,u.team,3);if u.id==playerID{sound("spell")}
    }
    func cast(_ index:Int,by u:ArenaUnit,direction:V2?=nil) {
        guard (0...2).contains(index),u.alive,u.stun<=0,u.ranks[index]>0,u.cooldowns[index]<=0 else{return}
        let spec=u.def.abilities[index];let cost=spec.mana*(u.blueBuff>0 ? 0.65:1);guard u.mana>=cost else{if u.id==playerID{message="Not enough mana";messageUntil=time+1.5};return}
        let nearest=enemies(of:u,range:spec.range+3).filter{!$0.structure}.min{$0.p.distance(u.p)<$1.p.distance(u.p)}
        let dir=(direction ?? nearest.map{($0.p-u.p).normalized} ?? u.facing).normalized
        if spec.kind == .execute && nearest == nil {return}
        u.mana-=cost;u.cooldowns[index]=spec.cooldown*(1-u.cdr);u.facing=dir;u.recall=0;u.revealed=2;u.attackPose=0.4
        let magic=u.def.role == .mage || u.def.role == .support
        let power=spec.power+Double(u.ranks[index]-1)*45+(magic ? u.stat(\.magic)*0.9:u.attack*0.65)
        if u.id==playerID {sound(index==2 ? "ultimate":"skill")}
        switch spec.kind {
        case .bolt,.pull:
            missiles.append(Missile(source:u.id,p:u.p,direction:dir,distance:spec.range,speed:24,width:spec.kind == .pull ? 0.8:1.1,damage:power,magic:magic,root:u.def.role == .support,homing:nil));fx(spec.kind == .pull ? "hook":"cast",u.p,u.p+dir*spec.range,u.team,spec.kind == .pull ? 1:0,0.3)
            if spec.kind == .pull,let t=nearest,pointDistance(t.p,u.p,u.p+dir*spec.range)<1.7 {t.p=u.p+dir*2;t.stun=t.immunity>0 ? 0:1}
        case .cleave:
            for t in enemies(of:u,range:spec.range) where !t.structure && (t.p-u.p).normalized.dot(dir)>0.25{damage(t,amount:power,source:u,magic:magic);t.slow=1.8};fx("cone",u.p,u.p+dir*spec.range,u.team,spec.range,0.4)
        case .dash:
            let start=u.p;blink(u,dir:dir,distance:spec.range);for t in enemies(of:u,range:spec.range+2) where !t.structure && pointDistance(t.p,start,u.p)<2{damage(t,amount:power,source:u,magic:magic)};u.hasteBuff=3
        case .blink:blink(u,dir:dir,distance:spec.range);u.conceal=1.8
        case .nova:
            for t in enemies(of:u,range:spec.range) where !t.structure{damage(t,amount:power,source:u,magic:magic);if t.immunity<=0{t.stun=index==2 ? 1.4:0.8}};fx("nova",u.p,u.p,u.team,spec.range,0.65)
        case .heal:
            for ally in heroes where ally.team==u.team && ally.alive && ally.p.distance(u.p)<spec.range {let amount=min(power,ally.maxHP-ally.hp);ally.hp+=amount;u.healing+=amount;fx("heal",ally.p,ally.p,u.team,amount,0.7)}
        case .shield:
            for ally in heroes where ally.team==u.team && ally.alive && ally.p.distance(u.p)<spec.range{ally.shield=max(ally.shield,power);ally.shieldTime=6;fx("shield",ally.p,ally.p,u.team,2,0.6)}
        case .volley:
            for i in -3...3 {let a=Double(i)*0.10;let d=V2(dir.x*cos(a)-dir.y*sin(a),dir.x*sin(a)+dir.y*cos(a));missiles.append(Missile(source:u.id,p:u.p,direction:d,distance:spec.range,speed:23,width:0.7,damage:power*0.32,magic:magic,root:false,homing:nil))};u.hasteBuff=5
        case .execute:
            if let t=nearest,t.p.distance(u.p)<=spec.range {blink(u,dir:(t.p-u.p),distance:max(0,t.p.distance(u.p)-1.2));damage(t,amount:power+(t.maxHP-t.hp)*0.23,source:u,magic:false);fx("nova",t.p,t.p,u.team,2.5,0.4);if !t.alive{u.cooldowns[index]*=0.35}}
        case .cyclone:u.cycloning=4;u.cycleTick=0;u.damageBuff=power
        case .meteor:
            let distance=direction == nil ? min(spec.range,nearest.map{$0.p.distance(u.p)} ?? spec.range*0.65):min(spec.range,max(2,(direction?.length ?? 1)*spec.range))
            let center=Battlefield.clamp(u.p+dir*distance);for i in 0..<3{blasts.append(DelayedBlast(source:u.id,point:center,delay:0.65+Double(i)*0.45,power:power/3))};fx("warning",center,center,u.team,3.8,0.65)
        }
    }
    func attack(_ u:ArenaUnit,_ target:ArenaUnit) {
        guard u.alive,target.alive,u.attackTimer<=0,u.stun<=0,target.p.distance(u.p)<=u.range+0.7 else{return}
        if target.structure && !vulnerable(target){return}
        u.attackTimer=u.attackInterval;u.facing=(target.p-u.p).normalized;u.recall=0;u.conceal=0;u.revealed=2;u.hits+=1;u.attackPose=0.27
        var power=u.attack;var critical=false
        if u.isHero {
            if u.def.role == .marksman && u.hits%4==0 || random()<u.stat(\.crit){power*=1.85;critical=true}
            if u.def.role == .assassin && !heroes.contains(where:{$0.id != target.id && $0.team==target.team && $0.alive && $0.p.distance(target.p)<5}){power*=1.18}
            if u.def.role == .tank && u.hits%4==0 {u.shield=max(u.shield,u.maxHP*0.06);u.shieldTime=4}
            if u.def.role == .mage && u.hits%3==0 {target.slow=1.5}
            if u.redBuff>0 {power*=1.1;target.slow=max(target.slow,1)}
        }
        if u.structure {if u.target==target.id {u.towerShots+=1}else{u.towerShots=0};u.target=target.id;power*=1+min(1.5,Double(u.towerShots)*0.25)}
        if u.range>4 {missiles.append(Missile(source:u.id,p:u.p,direction:u.facing,distance:u.range+5,speed:u.structure ? 22:28,width:0.3,damage:power,magic:false,root:false,homing:target.id))}else{damage(target,amount:power,source:u,magic:false);fx(critical ? "critical":"slash",u.p,target.p,u.team,power)}
        if u.id==playerID {sound("attack")}
    }
    func damage(_ target:ArenaUnit,amount:Double,source:ArenaUnit,magic:Bool,trueDamage:Bool=false) {
        guard target.alive,winner==nil else{return};if target.structure && !vulnerable(target){return}
        let defense=max(0,(magic ? target.resist:target.armor)-source.stat(\.penetration));var dealt=max(0,amount)*(trueDamage ? 1:120/(120+defense))
        if target.structure && !units.contains(where:{$0.team==source.team && $0.alive && !$0.isHero && !$0.structure && !$0.neutral && $0.p.distance(target.p)<9}){dealt*=0.25}
        if practice && target.id==playerID {dealt*=0.25}
        let absorbed=min(target.shield,dealt);target.shield-=absorbed;dealt-=absorbed;target.hp-=dealt;target.attackedAt=time;target.recall=0;target.regenerate=0;target.revealed=2.5;target.attackPose=max(target.attackPose,0.08)
        if source.isHero{target.attackers[source.id]=time;source.dealt+=dealt;if !magic && !target.structure {let steal=source.stat(\.lifesteal)+(source.def.role == .fighter ? 0.10:0);source.hp=min(source.maxHP,source.hp+dealt*steal)}}
        fx("damage",target.p,target.p,source.team,dealt,0.65)
        if target.isHero && source.isHero {for tower in units where tower.structure && tower.team==target.team && tower.alive && tower.p.distance(source.p)<tower.range{tower.target=source.id}}
        if target.hp<=0 {kill(target,by:source)}
    }
    func kill(_ target:ArenaUnit,by source:ArenaUnit) {
        target.hp=0;target.shield=0;target.cycloning=0;target.recall=0;fx("death",target.p,target.p,target.team,3,0.75)
        if target.isHero {
            target.deaths+=1;target.respawn=8+Double(target.level)*2+min(20,time/90)
            let killer=source.isHero ? source : target.attackers.filter{time-$0.value<8}.max{$0.value<$1.value}.flatMap{unit($0.key)}
            if let k=killer {k.kills+=1;k.streak+=1;gain(k,xp:160+Double(target.level)*25,gold:200+Double(min(5,target.streak))*80);for (id,when) in target.attackers where id != k.id && time-when<8 {if let a=unit(id),a.team==k.team {a.assists+=1;gain(a,xp:80,gold:90)}};say("\(k.name) defeated \(target.name)",k.team);sound("kill")}
            target.streak=0;target.attackers.removeAll();if target.id==playerID{attacking=false;movement = .zero}
        } else if target.structure {
            say(target.kind == .core ? (source.team==0 ? "Victory — enemy Nexus destroyed":"Defeat — your Nexus has fallen") : "\(source.team==0 ? "Allied":"Enemy") team destroyed a turret",source.team)
            for h in heroes where h.team==source.team {gain(h,xp:60,gold:target.kind == .core ? 0:120)}
            if target.kind == .core{winner=source.team;sound(source.team==0 ? "victory":"defeat")}
        } else if target.neutral {
            if target.kind == .camp {target.respawn=75;gain(source,xp:180,gold:110);if source.isHero{if target.tier==1 {source.blueBuff=75}else if target.tier==2 {source.redBuff=75}}}
            else {
                target.respawn=target.kind == .sentinel ? (time<420 ? 120:99999):180
                for h in heroes where h.team==source.team{gain(h,xp:220,gold:250);if target.kind == .sentinel{h.shield=max(h.shield,350);h.shieldTime=40}}
                if target.kind == .colossus {let lane=(0...2).min{l,r in units.filter{$0.kind == .tower && $0.team != source.team && $0.lane==l && $0.alive}.count < units.filter{$0.kind == .tower && $0.team != source.team && $0.lane==r && $0.alive}.count} ?? 1;_=add(.summoned,source.team,Battlefield.bases[source.team],9500,lane:lane)}
                say("\(source.team==0 ? "Allies":"Enemies") secured \(target.name)",source.team);sound("objective")
            }
        } else {
            let nearby=heroes.filter{$0.team==source.team && $0.alive && $0.p.distance(target.p)<13}
            for h in nearby {gain(h,xp:(target.kind == .siege ? 90:55)/Double(max(1,nearby.count)),gold:h.id==source.id ? (target.kind == .siege ? 85:55):30)}
        }
    }
    func step(_ dtIn:Double) {
        guard !paused,winner==nil else{return};let dt=min(0.05,max(0,dtIn));time+=dt
        effects=effects.compactMap{var f=$0;f.ttl-=dt;return f.ttl>0 ? f:nil}
        if time>=nextWave{spawnWave();nextWave+=30}
        if time>=nextIncome{for h in heroes{gain(h,xp:0,gold:time>8 ? 2:0);if h.id != playerID || autoplay {if let item=recommended(for:h){_=buy(item.id,for:h)}}};nextIncome+=1}
        for u in units {
            u.lastPosition=u.p
            if !u.alive {if u.respawn>0{u.respawn=max(0,u.respawn-dt);if u.respawn==0 {u.p=u.home;u.hp=u.maxHP;u.mana=u.maxMana;u.attackedAt=time-10;u.target=nil;if u.id==playerID{sound("respawn")}}};continue}
            u.attackTimer=max(0,u.attackTimer-dt);u.attackPose=max(0,u.attackPose-dt);u.stun=max(0,u.stun-dt);u.slow=max(0,u.slow-dt);u.conceal=max(0,u.conceal-dt);u.revealed=max(0,u.revealed-dt);u.speedBuff=max(0,u.speedBuff-dt);u.hasteBuff=max(0,u.hasteBuff-dt);u.blueBuff=max(0,u.blueBuff-dt);u.redBuff=max(0,u.redBuff-dt);u.immunity=max(0,u.immunity-dt);u.spellCD=max(0,u.spellCD-dt);u.regenCD=max(0,u.regenCD-dt);u.shieldTime=max(0,u.shieldTime-dt);if u.shieldTime==0{u.shield=0};u.cooldowns=u.cooldowns.map{max(0,$0-dt)}
            if u.isHero {
                u.mana=min(u.maxMana,u.mana+dt*(u.blueBuff>0 ? 18:8));u.hp=min(u.maxHP,u.hp+dt*3)
                if u.p.distance(Battlefield.bases[u.team])<6 {u.hp=min(u.maxHP,u.hp+u.maxHP*0.15*dt);u.mana=min(u.maxMana,u.mana+u.maxMana*0.20*dt)}
                if u.regenerate>0{u.regenerate-=dt;u.hp=min(u.maxHP,u.hp+u.maxHP*0.04*dt);u.mana=min(u.maxMana,u.mana+u.maxMana*0.04*dt)}
                if u.recall>0 {u.recall-=dt;if u.recall<=0{u.p=Battlefield.bases[u.team];fx("blink",u.p,u.p,u.team);if u.id==playerID{sound("recall")}};continue}
                if u.cycloning>0 {u.cycloning-=dt;u.cycleTick-=dt;if u.cycleTick<=0 {for t in enemies(of:u,range:5.5) where !t.structure{damage(t,amount:u.damageBuff/8,source:u,magic:false)};fx("nova",u.p,u.p,u.team,5,0.35);u.cycleTick=0.5}}
                if u.def.role == .support {for h in heroes where h.team==u.team && h.alive && time-h.attackedAt>5 && h.p.distance(u.p)<7{h.hp=min(h.maxHP,h.hp+dt*12)}}
                if u.id==playerID && !autoplay {if movement.length>0.05{move(u,direction:movement,dt:dt)};if attacking {playerAttack(u)}}else{bot(u,dt:dt)}
            }else if u.structure {towerAI(u)}else if u.neutral{neutralAI(u,dt:dt)}else{minionAI(u,dt:dt)}
        }
        updateMissiles(dt)
        var remaining:[DelayedBlast]=[]
        for var blast in blasts {blast.delay-=dt;if blast.delay<=0 {if let source=unit(blast.source){for t in units where t.alive && t.team != source.team && !t.structure && t.p.distance(blast.point)<3.8{damage(t,amount:blast.power,source:source,magic:true);if t.immunity<=0{t.stun=max(t.stun,0.5)}};fx("meteor",blast.point,blast.point,source.team,3.8,0.65)}}else{remaining.append(blast)}};blasts=remaining
        units.removeAll{!$0.alive && !$0.isHero && !$0.structure && !$0.neutral}
    }
    func playerAttack(_ u:ArenaUnit){
        var candidates=enemies(of:u,range:u.range+1)
        if attackMode==1 {candidates=candidates.filter{!$0.isHero && !$0.structure}}
        if attackMode==2 {candidates=candidates.filter{$0.structure}}
        let locked=selectedTarget.flatMap{unit($0)}.flatMap{$0.alive && visible($0,to:u.team) && $0.p.distance(u.p)<=u.range+0.7 ? $0:nil}
        let target=locked ?? candidates.sorted{a,b in
            if attackMode==0 && a.isHero != b.isHero{return a.isHero};if a.structure != b.structure{return !a.structure};return a.hp/a.maxHP < b.hp/b.maxHP
        }.first
        if let target=target {attack(u,target)}
    }
    func spawnWave(){for team in 0...1 {for lane in 0...2 {for i in 0..<3 {let siege=i==2;let kind:UnitKind=siege ? .siege : i==1 ? .caster:.melee;let hp=(siege ? 650.0:420.0)*(1+time/900);let u=add(kind,team,Battlefield.bases[team]+V2(Double(i)*0.6,Double(i)*0.5),hp,lane:lane);if !units.contains(where:{$0.team != team && $0.kind == .tower && $0.lane==lane && $0.tier==3 && $0.alive}){u.baseHP*=1.6;u.hp=u.baseHP}}}}}
    func minionAI(_ u:ArenaUnit,dt:Double) {
        let foes=enemies(of:u,range:u.range+2,includeNeutral:false).filter{!$0.structure || vulnerable($0)}
        if let t=foes.sorted(by:{a,b in if a.structure != b.structure{return !a.structure};return a.p.distance(u.p)<b.p.distance(u.p)}).first {if t.p.distance(u.p)<=u.range+0.6{attack(u,t)}else{walk(u,to:t.p,dt:dt)};return}
        let path=u.team==0 ? Battlefield.lanes[u.lane]:Array(Battlefield.lanes[u.lane].reversed());u.waypoint=min(u.waypoint,path.count-1);if u.p.distance(path[u.waypoint])<2.5{u.waypoint=min(path.count-1,u.waypoint+1)};walk(u,to:path[u.waypoint],dt:dt)
    }
    func towerAI(_ u:ArenaUnit) {
        let nearby=units.filter{$0.alive && $0.team != u.team && !$0.neutral && !$0.structure && $0.p.distance(u.p)<=u.range}
        let locked=u.target.flatMap{unit($0)}.flatMap{$0.alive && $0.p.distance(u.p)<=u.range && visible($0,to:u.team) ? $0:nil}
        if let target=locked ?? nearby.sorted(by:{a,b in if a.isHero != b.isHero{return !a.isHero};return a.p.distance(u.p)<b.p.distance(u.p)}).first{attack(u,target)}else{u.target=nil;u.towerShots=0}
    }
    func neutralAI(_ u:ArenaUnit,dt:Double) {
        guard time-u.attackedAt<8 else {if u.p.distance(u.home)>0.5{walk(u,to:u.home,dt:dt);u.hp=min(u.maxHP,u.hp+u.maxHP*0.15*dt)};return}
        if u.p.distance(u.home)>9{u.attackedAt = -100;return}
        if let t=units.filter({$0.alive && !$0.neutral && !$0.structure && $0.p.distance(u.p)<8}).min(by:{$0.p.distance(u.p)<$1.p.distance(u.p)}) {if t.p.distance(u.p)<u.range+0.6{attack(u,t)}else{walk(u,to:t.p,dt:dt)}}
    }
    func bot(_ u:ArenaUnit,dt:Double) {
        if u.stun>0{return}
        if u.hp/u.maxHP<0.24 || (u.p.distance(Battlefield.bases[u.team])<7 && u.hp/u.maxHP<0.86) {walk(u,to:Battlefield.bases[u.team],dt:dt);if u.hp/u.maxHP<0.18 && u.spellCD<=0 && u.spell == .flicker {castSpell(u,dir:Battlefield.bases[u.team]-u.p)};return}
        u.aiTimer-=dt
        if u.aiTimer<=0 {
            u.aiTimer=difficulty == .veteran ? 0.18:difficulty == .casual ? 0.65:0.35
            let foes=enemies(of:u,range:13,includeNeutral:false)
            let enemyHero=foes.filter{$0.isHero}.min{$0.hp/$0.maxHP<$1.hp/$1.maxHP}
            let allies=heroes.filter{$0.team==u.team && $0.alive && $0.p.distance(u.p)<12}.count
            if let threat=enemyHero,foes.filter({$0.isHero}).count>allies+1 && u.hp/u.maxHP<0.7 {u.aiDestination=u.p+(u.p-threat.p).normalized*6;u.target=nil}
            else if let h=enemyHero {u.target=h.id;u.aiDestination=h.p}
            else {
                let target=foes.filter{!$0.structure || vulnerable($0)}.min{$0.p.distance(u.p)<$1.p.distance(u.p)}
                u.target=target?.id
                if let t=target {u.aiDestination=t.p}
                else if u.def.role == .assassin,let camp=units.filter({$0.neutral && $0.alive && ($0.kind == .camp || time>150) && $0.p.distance(u.p)<35}).min(by:{$0.p.distance(u.p)<$1.p.distance(u.p)}) {u.target=camp.id;u.aiDestination=camp.p}
                else if time>150,let boss=units.first(where:{$0.neutral && $0.alive && $0.kind != .camp && $0.p.distance(u.p)<23}),allies>=2 {u.target=boss.id;u.aiDestination=boss.p}
                else if u.team==0 && pingUntil>time,let point=pingPoint,u.p.distance(point)<35 {u.aiDestination=point}
                else {let enemyTower=units.filter{$0.team != u.team && $0.structure && $0.alive && ($0.lane==u.lane || $0.kind == .core) && vulnerable($0)}.min{$0.p.distance(u.p)<$1.p.distance(u.p)}
                    let targetPoint=enemyTower?.p ?? Battlefield.bases[1-u.team]
                    let nearest=(0...100).min { Battlefield.point(lane:u.lane,progress:Double($0)/100).distance(u.p)<Battlefield.point(lane:u.lane,progress:Double($1)/100).distance(u.p) } ?? 0
                    let ahead=max(0,min(100,nearest+(u.team==0 ? 8 : -8)))
                    u.aiDestination = u.p.distance(targetPoint)<16 ? targetPoint:Battlefield.point(lane:u.lane,progress:Double(ahead)/100)
                }
            }
        }
        if let t=u.target.flatMap({unit($0)}),t.alive,(t.neutral || visible(t,to:u.team)) {
            let d=t.p.distance(u.p)
            if t.structure && !units.contains(where:{$0.team==u.team && $0.alive && !$0.isHero && !$0.structure && $0.p.distance(t.p)<8}){walk(u,to:u.p+(u.p-t.p).normalized*6,dt:dt);return}
            if !t.structure && d<12 {
                for i in [2,0,1] {let spec=u.def.abilities[i];if d<spec.range+0.5 || spec.kind == .shield || spec.kind == .heal {cast(i,by:u,direction:t.p-u.p)}}
                if t.neutral && u.spell == .retribution && t.hp<600+Double(u.level)*100 {castSpell(u)}
            }
            if d<=u.range+0.5 {attack(u,t);if u.range>5 && d<4 {walk(u,to:u.p+(u.p-t.p).normalized*4,dt:dt)}}else{walk(u,to:t.p,dt:dt)}
        }else{walk(u,to:u.aiDestination,dt:dt)}
    }
    func updateMissiles(_ dt:Double){
        var next:[Missile]=[]
        for var m in missiles {guard let s=unit(m.source) else{continue};var direction=m.direction
            if let id=m.homing {guard let target=unit(id),target.alive else{continue};direction=(target.p-m.p).normalized}
            let previous=m.p;m.p=m.p+direction*m.speed*dt;m.distance-=m.speed*dt
            var consumed=false
            for t in units where t.alive && t.team != s.team && !m.hit.contains(t.id) && (m.homing == nil ? !t.structure:t.id==m.homing) {
                if pointDistance(t.p,previous,m.p)<m.width+(t.structure ? 1.2:0.6) {damage(t,amount:m.damage,source:s,magic:m.magic);if m.root && t.immunity<=0{t.stun=1};if s.def.id==9{t.slow=1.8};m.hit.insert(t.id);if m.homing != nil {consumed=true;break}}
            }
            fx("projectile",previous,m.p,s.team,m.magic ? 1:0,0.10)
            if m.distance>0 && !consumed{next.append(m)}
        };missiles=next
    }
    func pointDistance(_ p:V2,_ a:V2,_ b:V2)->Double{let d=b-a;let n=d.dot(d);let t=n<0.0001 ? 0:max(0,min(1,(p-a).dot(d)/n));return p.distance(a+d*t)}
    func ping(_ p:V2,mode:Int=0){pingPoint=p;pingUntil=time+6;pingMode=mode;message=["Attack this position","Fall back","Group up"][max(0,min(2,mode))];messageUntil=time+3;sound("ping")}
}
