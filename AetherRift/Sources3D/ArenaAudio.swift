import AVFoundation
import UIKit

@MainActor final class ArenaAudio {
    static let shared=ArenaAudio();var enabled=true;private var cache:[String:Data]=[:];private var players:[AVAudioPlayer]=[];private var music:AVAudioPlayer?
    func play(_ key:String){guard enabled else{return};if key=="attack" && players.count>6{return}
        if cache[key]==nil {let specs:[String:(Double,Double,Double)]=["attack":(0.08,230,80),"skill":(0.20,460,1000),"ultimate":(0.55,120,640),"level":(0.45,440,1320),"purchase":(0.18,880,1100),"kill":(0.35,330,660),"objective":(0.65,140,550),"victory":(1.2,392,1176),"defeat":(0.8,330,110),"recall":(0.45,330,660),"heal":(0.3,520,780),"respawn":(0.5,440,880),"spell":(0.3,220,900),"ping":(0.15,770,990)]
            let s=specs[key] ?? (0.08,550,800);cache[key]=wave(duration:s.0,start:s.1,end:s.2,music:false)}
        guard let data=cache[key],let player=try? AVAudioPlayer(data:data) else{return};players.removeAll{!$0.isPlaying};if players.count>12{players.removeFirst()};player.volume=0.23;player.play();players.append(player)
    }
    func start(){guard enabled else{return};try? AVAudioSession.sharedInstance().setCategory(.ambient,mode:.default,options:.mixWithOthers);try? AVAudioSession.sharedInstance().setActive(true)
        if music==nil{music=try? AVAudioPlayer(data:wave(duration:12,start:110,end:110,music:true));music?.numberOfLoops = -1;music?.volume=0.08};music?.play()
    }
    func stop(){music?.stop();players.forEach{$0.stop()};players=[]}
    private func wave(duration:Double,start:Double,end:Double,music:Bool)->Data {
        let rate=22050;let count=Int(duration*Double(rate));var samples=[Int16](repeating:0,count:count);var phase=0.0
        for i in 0..<count {let t=Double(i)/Double(rate);let progress=Double(i)/Double(count);var value:Double
            if music {let notes=[220.0,261.63,329.63,293.66,220,196,261.63,329.63];let beat=Int(t*2)%notes.count;let env=exp(-(t*2-Double(Int(t*2)))*3);value=sin(t*2 * .pi*notes[beat])*env*0.20+sin(t*2 * .pi*110)*0.12+sin(t*2 * .pi*164.81)*0.07}
            else {let hz=start+(end-start)*progress;phase+=2 * .pi*hz/Double(rate);let env=min(1,progress*25)*pow(1-progress,1.8);value=(sin(phase)+sin(phase*2.01)*0.25)*env*0.6};samples[i]=Int16(max(-1,min(1,value))*30000)
        }
        var data=Data();func str(_ s:String){data.append(s.data(using:.ascii)!)};func n32(_ n:UInt32){var v=n.littleEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)}};func n16(_ n:UInt16){var v=n.littleEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)}}
        str("RIFF");n32(UInt32(36+count*2));str("WAVEfmt ");n32(16);n16(1);n16(1);n32(UInt32(rate));n32(UInt32(rate*2));n16(2);n16(16);str("data");n32(UInt32(count*2));samples.withUnsafeBytes{data.append(contentsOf:$0)};return data
    }
}
