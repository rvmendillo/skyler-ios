import Foundation

struct V2: Equatable {
    var x: Double; var y: Double
    static let zero = V2(x: 0, y: 0)
    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    init(x: Double, y: Double) { self.x = x; self.y = y }
    static func + (a: V2, b: V2) -> V2 { V2(a.x+b.x,a.y+b.y) }
    static func - (a: V2, b: V2) -> V2 { V2(a.x-b.x,a.y-b.y) }
    static func * (a: V2, b: Double) -> V2 { V2(a.x*b,a.y*b) }
    var length: Double { sqrt(x*x+y*y) }
    var normalized: V2 { length > 0.001 ? self * (1/length) : V2(0,1) }
    func distance(_ p: V2) -> Double { (self-p).length }
    func dot(_ p: V2) -> Double { x*p.x+y*p.y }
}
enum Role: String, CaseIterable {
    case tank = "Tank", fighter = "Fighter", assassin = "Assassin", mage = "Mage", marksman = "Marksman", support = "Support"
    var icon: String { switch self { case .tank: return "shield.lefthalf.filled"; case .fighter: return "flame.fill"; case .assassin: return "bolt.fill"; case .mage: return "sparkles"; case .marksman: return "scope"; case .support: return "cross.case.fill" } }
    var lane: Int { switch self { case .fighter: return 0; case .mage, .assassin: return 1; default: return 2 } }
}
enum AbilityKind: String { case cleave, dash, bolt, nova, heal, shield, volley, blink, execute, pull, cyclone, meteor }
struct Ability {
    let name: String; let kind: AbilityKind; let cooldown: Double; let mana: Double; let range: Double; let power: Double; let detail: String
    var icon: String { switch kind { case .cleave,.cyclone: return "hurricane"; case .dash,.blink: return "arrow.up.forward"; case .bolt,.volley: return "location.north.fill"; case .nova,.meteor: return "sparkles"; case .heal: return "cross.fill"; case .shield: return "shield.fill"; case .execute: return "bolt.heart.fill"; case .pull: return "arrow.down.to.line" } }
}
struct HeroDef: Identifiable {
    let id: Int; let name: String; let title: String; let role: Role; let color: UInt32; let hp: Double; let attack: Double; let range: Double; let speed: Double; let passive: String; let abilities: [Ability]
}
func ability(_ name: String,_ kind: AbilityKind,_ cd: Double,_ mana: Double,_ range: Double,_ power: Double,_ detail: String) -> Ability {
    Ability(name:name,kind:kind,cooldown:cd,mana:mana,range:range,power:power,detail:detail)
}
enum Roster {
    static let heroes: [HeroDef] = [
        HeroDef(id:0,name:"Bastion",title:"Warden of the Dawn",role:.tank,color:0x4AD3DA,hp:2900,attack:105,range:2.7,speed:5.6,passive:"Every fourth attack grants a shield.",abilities:[ability("Sundering Guard",.cleave,7,45,4.8,180,"Sweep the frontline and slow enemies."),ability("Shield March",.dash,10,60,7,150,"Charge forward, damaging enemies on the path."),ability("Citadel Fall",.nova,38,110,6.5,460,"Slam the ground and stun nearby enemies.")]),
        HeroDef(id:1,name:"Kael",title:"The Emberblade",role:.fighter,color:0xF69D57,hp:2500,attack:130,range:2.8,speed:6.0,passive:"Basic attacks restore a portion of damage dealt.",abilities:[ability("Ember Arc",.cleave,5,35,5,220,"A wide blade arc that slows."),ability("Flame Step",.dash,9,50,6.5,170,"Lunge through enemies."),ability("Inferno Dance",.cyclone,32,100,5.2,500,"A four-second storm of spinning blades.")]),
        HeroDef(id:2,name:"Nyx",title:"Veil of Midnight",role:.assassin,color:0xB78AFF,hp:2100,attack:150,range:2.6,speed:6.5,passive:"Attacks deal bonus damage to isolated heroes.",abilities:[ability("Night Shard",.bolt,5,40,11,230,"Throw a piercing shard in the aimed direction."),ability("Veilwalk",.blink,11,55,7,100,"Blink forward and gain brief concealment."),ability("Final Eclipse",.execute,36,100,5.5,400,"Strike a nearby target; damage grows with missing health.")]),
        HeroDef(id:3,name:"Lyra",title:"Astral Arcanist",role:.mage,color:0x85ACFF,hp:2050,attack:95,range:6.2,speed:5.8,passive:"Every third basic attack slows its target.",abilities:[ability("Astral Spear",.bolt,5,50,12,280,"Fire a long-range piercing magic missile."),ability("Starlight Well",.nova,10,70,5,240,"Freeze nearby enemies in place."),ability("Falling Constellation",.meteor,40,120,13,660,"Call three delayed explosions at the aimed point.")]),
        HeroDef(id:4,name:"Orion",title:"The Sunstrider",role:.marksman,color:0xF1CF75,hp:2000,attack:135,range:7.8,speed:5.9,passive:"Every fourth attack critically strikes.",abilities:[ability("Sunpiercer",.bolt,6,45,13,250,"Loose an arrow through all enemies in a line."),ability("Wind Roll",.dash,10,45,6,90,"Reposition and accelerate basic attacks."),ability("Solar Barrage",.volley,36,100,13,550,"Fire a spread of seven sun arrows.")]),
        HeroDef(id:5,name:"Mira",title:"Keeper of Spring",role:.support,color:0x71E2AF,hp:2300,attack:88,range:6,speed:5.9,passive:"Nearby allies regenerate health while out of combat.",abilities:[ability("Bloomlight",.heal,8,60,7,290,"Restore health to nearby allied heroes."),ability("Rootweave",.bolt,8,55,10,170,"Send a rooting orb through enemies."),ability("Sanctuary",.shield,42,120,9,650,"Give nearby allies a powerful six-second shield.")]),
        HeroDef(id:6,name:"Torren",title:"The Stonebound",role:.tank,color:0xA9B9C1,hp:3050,attack:100,range:2.8,speed:5.5,passive:"Every fourth attack grants a shield.",abilities:[ability("Graviton Chain",.pull,10,55,10,180,"Hook the first enemy hero or creature in a line."),ability("Granite Skin",.shield,13,60,5,350,"Shield nearby allies."),ability("Worldbreaker",.nova,40,110,7,480,"Shatter the earth and stun enemies.")]),
        HeroDef(id:7,name:"Sera",title:"Tempest Duelist",role:.fighter,color:0xE892BA,hp:2400,attack:140,range:3,speed:6.2,passive:"Basic attacks restore a portion of damage dealt.",abilities:[ability("Gale Edge",.bolt,5,35,9,200,"Send a blade of wind through enemies."),ability("Crosswind",.dash,8,45,7,200,"Dash with a sweeping strike."),ability("Tempest Waltz",.cyclone,34,100,5.5,510,"Spin through the opposing frontline.")]),
        HeroDef(id:8,name:"Vesper",title:"The Gilded Fang",role:.assassin,color:0xDBA6FF,hp:2150,attack:145,range:2.7,speed:6.6,passive:"Attacks deal bonus damage to isolated heroes.",abilities:[ability("Twin Fangs",.cleave,5,35,4.5,240,"Cut a cone in front of you."),ability("Afterimage",.blink,10,50,8,80,"Blink and briefly conceal yourself."),ability("Dusk Sentence",.execute,34,100,6,390,"Finish wounded enemies with an empowered strike.")]),
        HeroDef(id:9,name:"Ione",title:"Oracle of Winter",role:.mage,color:0x75DDEF,hp:2100,attack:90,range:6.4,speed:5.7,passive:"Every third basic attack slows its target.",abilities:[ability("Glacial Lance",.bolt,5,45,12,270,"A freezing lance slows every enemy hit."),ability("Crystal Halo",.shield,12,70,6,330,"Wrap nearby allies in crystal shields."),ability("Winter's Descent",.meteor,39,120,13,680,"Three frost impacts stun enemies in the target area.")]),
        HeroDef(id:10,name:"Flint",title:"The Rift Ranger",role:.marksman,color:0xE6B07B,hp:2050,attack:140,range:7.5,speed:5.8,passive:"Every fourth attack critically strikes.",abilities:[ability("Railshot",.bolt,6,40,14,270,"Fire a piercing shot across the lane."),ability("Recoil Step",.dash,10,40,6,100,"Dash and gain attack speed."),ability("Horizon Salvo",.volley,37,100,14,580,"Unleash a cone of explosive projectiles.")]),
        HeroDef(id:11,name:"Auri",title:"The Dawn Cantor",role:.support,color:0xF6DFC0,hp:2250,attack:92,range:6.3,speed:6.0,passive:"Nearby allies regenerate health while out of combat.",abilities:[ability("Renewal Song",.heal,8,55,8,310,"Heal nearby teammates."),ability("Resonance",.nova,10,60,5,200,"Release a stunning note around you."),ability("Dawn Chorus",.shield,40,110,10,700,"Protect your team with a radiant shield.")])
    ]
}
enum ItemGroup: String, CaseIterable { case movement = "Movement", physical = "Physical", magic = "Magic", defense = "Defense" }
struct Equipment: Identifiable {
    let id: Int; let name: String; let group: ItemGroup; let cost: Int
    var attack: Double = 0; var magic: Double = 0; var hp: Double = 0; var armor: Double = 0; var resist: Double = 0; var speed: Double = 0; var haste: Double = 0; var attackSpeed: Double = 0; var lifesteal: Double = 0; var crit: Double = 0; var penetration: Double = 0
    var component: Int? = nil
    var icon: String { switch group { case .movement: return "shoe.fill"; case .physical: return "bolt.fill"; case .magic: return "sparkles"; case .defense: return "shield.fill" } }
    var description: String {
        var p:[String]=[]
        if attack > 0 { p.append("+\(Int(attack)) Attack") }; if magic > 0 { p.append("+\(Int(magic)) Magic") }; if hp > 0 { p.append("+\(Int(hp)) HP") }; if armor > 0 { p.append("+\(Int(armor)) Armor") }; if resist > 0 { p.append("+\(Int(resist)) Resist") }; if speed > 0 { p.append("+\(Int(speed*100))% Move") }; if haste > 0 { p.append("+\(Int(haste*100))% Haste") }; if attackSpeed > 0 { p.append("+\(Int(attackSpeed*100))% AS") }; if lifesteal > 0 { p.append("+\(Int(lifesteal*100))% Lifesteal") }; if crit > 0 { p.append("+\(Int(crit*100))% Crit") }; if penetration > 0 { p.append("+\(Int(penetration)) Pen") }; return p.joined(separator:" · ")
    }
}
enum Armory {
    static let items:[Equipment] = [
        Equipment(id:0,name:"Trail Boots",group:.movement,cost:250,speed:0.10),
        Equipment(id:1,name:"Iron Shard",group:.physical,cost:300,attack:18),
        Equipment(id:2,name:"Aether Stone",group:.magic,cost:300,magic:25),
        Equipment(id:3,name:"Vital Crystal",group:.defense,cost:300,hp:230),
        Equipment(id:4,name:"Chain Vest",group:.defense,cost:350,armor:20),
        Equipment(id:5,name:"Ward Charm",group:.defense,cost:350,resist:20),
        Equipment(id:6,name:"Storm Greaves",group:.movement,cost:700,speed:0.22,attackSpeed:0.15,component:0),
        Equipment(id:7,name:"Sage Treads",group:.movement,cost:700,magic:25,speed:0.22,haste:0.10,component:0),
        Equipment(id:8,name:"Bastion Boots",group:.movement,cost:700,armor:25,speed:0.22,component:0),
        Equipment(id:9,name:"Dawnblade",group:.physical,cost:1650,attack:70,crit:0.20,component:1),
        Equipment(id:10,name:"Bloodthorn",group:.physical,cost:1850,attack:65,lifesteal:0.20,component:1),
        Equipment(id:11,name:"Windspindle",group:.physical,cost:1700,attack:30,attackSpeed:0.40,crit:0.15,component:1),
        Equipment(id:12,name:"Riftbreaker",group:.physical,cost:2050,attack:85,penetration:40,component:1),
        Equipment(id:13,name:"Eclipse Edge",group:.physical,cost:1900,attack:65,haste:0.15,penetration:20,component:1),
        Equipment(id:14,name:"Titan Cleaver",group:.physical,cost:2200,attack:90,hp:350,component:1),
        Equipment(id:15,name:"Star Codex",group:.magic,cost:1700,magic:100,haste:0.10,component:2),
        Equipment(id:16,name:"Void Prism",group:.magic,cost:2050,magic:110,penetration:40,component:2),
        Equipment(id:17,name:"Winter Orb",group:.magic,cost:1850,magic:80,hp:350,armor:20,component:2),
        Equipment(id:18,name:"Dawn Chalice",group:.magic,cost:1800,magic:65,hp:400,haste:0.20,component:2),
        Equipment(id:19,name:"Astral Crown",group:.magic,cost:2400,magic:170,component:2),
        Equipment(id:20,name:"Citadel Plate",group:.defense,cost:1900,hp:650,armor:70,component:4),
        Equipment(id:21,name:"Spirit Mantle",group:.defense,cost:1850,hp:650,resist:70,component:5),
        Equipment(id:22,name:"Heart of Oak",group:.defense,cost:2100,hp:1250,haste:0.10,component:3),
        Equipment(id:23,name:"Guardian Aegis",group:.defense,cost:2300,hp:850,armor:35,resist:35,component:3)
    ]
    static func build(for role: Role) -> [Int] {
        switch role { case .tank: return [8,20,21,22,23,14]; case .fighter: return [8,10,14,13,20,21]; case .assassin: return [6,13,12,10,9,23]; case .mage: return [7,15,16,19,17,18]; case .marksman: return [6,9,11,10,12,14]; case .support: return [7,18,21,22,15,23] }
    }
}
enum BattleSpell: String, CaseIterable { case flicker = "Flicker", sprint = "Sprint", purify = "Purify", retribution = "Retribution"
    var icon:String { switch self { case .flicker:return "bolt.fill"; case .sprint:return "figure.run"; case .purify:return "sun.max.fill"; case .retribution:return "flame.fill" } }
    var cooldown:Double { switch self { case .flicker:return 120; case .sprint:return 90; case .purify:return 90; case .retribution:return 35 } }
}
enum Difficulty: String, CaseIterable { case casual = "Casual", standard = "Standard", veteran = "Veteran" }
enum TargetPriority:String,CaseIterable {case lowestHealth="Lowest HP",lowestPercent="Lowest HP %",closest="Closest"}
struct Rock { let position: V2; let radius: Double }
enum Battlefield {
    static let bases=[V2(8,8),V2(92,92)]
    static let lanes:[[V2]]=[ [V2(8,8),V2(9,35),V2(10,69),V2(16,87),V2(48,91),V2(72,92),V2(92,92)], [V2(8,8),V2(27,27),V2(50,50),V2(73,73),V2(92,92)], [V2(8,8),V2(35,9),V2(69,10),V2(87,16),V2(91,48),V2(92,72),V2(92,92)] ]
    static let brush:[V2]=[V2(18,45),V2(16,76),V2(35,70),V2(44,61),V2(60,45),V2(69,34),V2(76,16),V2(45,18),V2(82,55),V2(55,82),V2(38,40),V2(62,60)]
    static let rocks:[Rock]=[Rock(position:V2(23,41),radius:3.8),Rock(position:V2(29,46),radius:3),Rock(position:V2(41,23),radius:3.8),Rock(position:V2(46,29),radius:3),Rock(position:V2(59,77),radius:3.8),Rock(position:V2(54,71),radius:3),Rock(position:V2(77,59),radius:3.8),Rock(position:V2(71,54),radius:3),Rock(position:V2(27,76),radius:3),Rock(position:V2(76,27),radius:3)]
    static func inBrush(_ p:V2) -> Int? { brush.firstIndex { $0.distance(p)<3.4 } }
    static func point(lane:Int,progress:Double)->V2 {
        let path=lanes[lane]; let lengths=zip(path,path.dropFirst()).map{$0.distance($1)}; let total=lengths.reduce(0,+); var remaining=max(0,min(1,progress))*total
        for i in 0..<lengths.count { if remaining<=lengths[i] {return path[i]+(path[i+1]-path[i])*(remaining/lengths[i])}; remaining-=lengths[i] }; return path.last!
    }
    static func clamp(_ p:V2)->V2 { V2(max(3,min(97,p.x)),max(3,min(97,p.y))) }
    static func walkable(_ p:V2,radius:Double=0.55)->Bool { p.x>=3 && p.y>=3 && p.x<=97 && p.y<=97 && !rocks.contains{$0.position.distance(p)<$0.radius+radius} }
}
