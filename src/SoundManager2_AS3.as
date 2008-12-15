/*
   SoundManager 2: Javascript Sound for the Web
   ----------------------------------------------
   http://schillmania.com/projects/soundmanager2/

   Copyright (c) 2008, Scott Schiller. All rights reserved.
   Code licensed under the BSD License:
   http://www.schillmania.com/projects/soundmanager2/license.txt

   V2.90a.20081028

   Flash 9 / ActionScript 3 version
*/

package {

import flash.display.Sprite;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.system.Security;
import flash.events.*;
import flash.media.Sound;
import flash.media.SoundChannel;
import flash.media.SoundMixer;
import flash.utils.setInterval;
import flash.utils.clearInterval;
import flash.utils.Dictionary;
import flash.utils.Timer;
import flash.net.URLLoader;
import flash.net.URLRequest;
import flash.xml.*;
import flash.external.ExternalInterface; // woo

public class SoundManager2_AS3 extends Sprite {

  // Cross-domain security exception stuffs
  // HTML on foo.com loading .swf hosted on bar.com? Define your "HTML domain" here to allow JS+Flash communication to work.
  // See http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/system/Security.html#allowDomain()
  // Security.allowDomain("foo.com");

  // externalInterface references (for Javascript callbacks)
  public var baseJSController:String = "soundManager";
  public var baseJSObject:String = baseJSController+".sounds";

  // internal objects
  public var sounds:Array = []; // indexed string array
  public var soundObjects:Dictionary = new Dictionary(); // associative Sound() object Dictionary type
  public var timerInterval:uint = 20;
  public var timer:Timer = null;
  public var pollingEnabled:Boolean = false; // polling (timer) flag - disabled by default, enabled by JS->Flash call
  public var debugEnabled:Boolean = true;    // Flash debug output enabled by default, disabled by JS call
  public var loaded:Boolean = false;

  public function SoundManager2_AS3() {

    stage.scaleMode = StageScaleMode.NO_SCALE; // SHOW_ALL vs. NO_SCALE vs. EXACT_FIT
    stage.align	= StageAlign.TOP_LEFT;

    ExternalInterface.addCallback('_load', _load);
    ExternalInterface.addCallback('_unload', _unload);
    ExternalInterface.addCallback('_stop', _stop);
    ExternalInterface.addCallback('_start', _start);
    ExternalInterface.addCallback('_pause', _pause);
    ExternalInterface.addCallback('_setPosition', _setPosition);
    ExternalInterface.addCallback('_setPan', _setPan);
    ExternalInterface.addCallback('_setVolume', _setVolume);
    ExternalInterface.addCallback('_setPolling', _setPolling);
    ExternalInterface.addCallback('_externalInterfaceTest', _externalInterfaceTest);
    ExternalInterface.addCallback('_disableDebug', _disableDebug);
    ExternalInterface.addCallback('_loadFromXML', _loadFromXML);
    ExternalInterface.addCallback('_createSound', _createSound);
    ExternalInterface.addCallback('_destroySound', _destroySound);

    // call after delay, to be safe (ensure callbacks are registered by the time JS is called below)
    var timer:Timer = new Timer(20,0);
    timer.addEventListener(TimerEvent.TIMER, function():void {
      _externalInterfaceTest(true);
      timer.reset();
    });
    timer.start();

    // delayed, see above
    // _externalInterfaceTest(true);

  } // SoundManager2()

  // methods
  // -----------------------------------

  public function writeDebug(s:String,bTimestamp:Boolean=false):Boolean {
    if (!debugEnabled) return false;
    ExternalInterface.call(baseJSController+"['_writeDebug']","(Flash): "+s,null,bTimestamp);
    return true;
  }

  public function _externalInterfaceTest(isFirstCall:Boolean):Boolean {
    if (isFirstCall == true) {
      writeDebug('Flash -&gt; JS OK');
      ExternalInterface.call(baseJSController+"._externalInterfaceOK");
    } else {
      writeDebug('_externalInterfaceTest(): JS &lt;-&gt; Flash OK');
      var sandboxType:String = flash.system.Security['sandboxType'];
      ExternalInterface.call(baseJSController+"._setSandboxType",sandboxType);
    }
    return true; // to verify that a call from JS to here, works. (eg. JS receives "true", thus OK.)
  }

  public function _disableDebug():void {
    // prevent future debug calls from Flash going to client (maybe improve performance)
    writeDebug('_disableDebug()');
    debugEnabled = false;
  }

  public function checkLoadProgress(e:Event):void {
try {
    var oSound:Object = e.target;
    var bL:int = oSound.bytesLoaded;
    var bT:int = oSound.bytesTotal;
    var nD:int = oSound.length||oSound.duration||0;
    var sMethod:String = baseJSObject+"['"+oSound.sID+"']._whileloading";
    ExternalInterface.call(sMethod,bL,bT,nD);
    if (bL && bT && bL != oSound.lastValues.bytes) {
      oSound.lastValues.bytes = bL;
      ExternalInterface.call(sMethod,bL,bT,nD);
    }
} catch(e:Error) {
  writeDebug('checkLoadProgress(): '+e.toString());
}
  }

  public function checkProgress():void {
    var bL:int = 0;
    var bT:int = 0;
    var nD:int = 0;
    var nP:int = 0;
    var lP:Number = 0;
    var rP:Number = 0;
    var oSound:SoundManager2_SMSound_AS3 = null;
    var oSoundChannel:flash.media.SoundChannel = null;
    var sMethod:String = null;
    var newPeakData:Boolean = false;
    var newWaveformData:Boolean = false;
    var newEQData:Boolean = false;

    for (var i:int=0,j:int=sounds.length; i<j; i++) {
      oSound = soundObjects[sounds[i]];
      sMethod = baseJSObject+"['"+sounds[i]+"']._whileloading";
      if (!oSound) continue; // if sounds are destructed within event handlers while this loop is running, may be null

      if (oSound.useNetstream) {
        bL = oSound.ns.bytesLoaded;
        bT = oSound.ns.bytesTotal;
        nD = int(oSound.duration||0); // can sometimes be null with short MP3s? Wack.
        nP = oSound.ns.time*1000;
        if (oSound.loaded != true && nD > 0 && bL == bT) {
          // non-MP3 has loaded
          // writeDebug('ns: time/duration/bytesloaded,total: '+(oSound.ns.time*1000)+', '+oSound.duration+', '+oSound.ns.bytesLoaded+'/'+oSound.ns.bytesTotal);
          oSound.loaded = true;
          try {
            ExternalInterface.call(baseJSObject+"['"+oSound.sID+"']._whileloading",oSound.ns.bytesLoaded,oSound.ns.bytesTotal,nD);
            ExternalInterface.call(baseJSObject+"['"+oSound.sID+"']._onload",oSound.duration>0?1:0);
	  } catch(e:Error) {
	    writeDebug('_whileLoading/_onload error: '+e.toString());
	  }
        } else if (!oSound.loaded && bL && bT && bL != oSound.lastValues.bytes) {
          oSound.lastValues.bytes = bL;
          ExternalInterface.call(sMethod,bL,bT,nD);
        }
      } else {
		oSoundChannel = oSound.soundChannel;
        bL = oSound.bytesLoaded;
        bT = oSound.bytesTotal;
        nD = int(oSound.length||0); // can sometimes be null with short MP3s? Wack.
        // writeDebug('loaded/total/duration: '+bL+', '+bT+', '+nD);
        if (oSoundChannel) {
          nP = (oSoundChannel.position||0);
          if (oSound.usePeakData) {
            lP = int((oSoundChannel.leftPeak)*1000)/1000;
            rP = int((oSoundChannel.rightPeak)*1000)/1000;
          } else {
	        lP = 0;
	        rP = 0;
          }
        } else {
          // stopped, not loaded or feature not used
          nP = 0;
        }
        // loading progress
        if (bL && bT && bL != oSound.lastValues.bytes) {
          oSound.lastValues.bytes = bL;
          ExternalInterface.call(sMethod,bL,bT,nD);
        }
      }

      // peak data
      if (oSoundChannel && oSound.usePeakData) {
        if (lP != oSound.lastValues.leftPeak) {
          oSound.lastValues.leftPeak = lP;
          newPeakData = true;
        }
        if (rP != oSound.lastValues.rightPeak) {
          oSound.lastValues.rightPeak = rP;
          newPeakData = true;
	    }
      }

      // raw waveform + EQ spectrum data
      if (oSoundChannel) {
	    if (oSound.useWaveformData) {
          try {
            oSound.getWaveformData();
          } catch(e:Error) {
            writeDebug('computeSpectrum() (waveform data) '+e.toString());
            oSound.useWaveformData = false;
          }
        }
	    if (oSound.useEQData) {
          try {
            oSound.getEQData();
          } catch(e:Error) {
            writeDebug('computeSpectrum() (EQ data) '+e.toString());
            oSound.useEQData = false;
          }
        }
        if (oSound.waveformDataArray != oSound.lastValues.waveformDataArray) {
          oSound.lastValues.waveformDataArray = oSound.waveformDataArray;
          newWaveformData = true;
        }
        if (oSound.eqDataArray != oSound.lastValues.eqDataArray) {
          oSound.lastValues.eqDataArray = oSound.eqDataArray;
          newEQData = true;
        }
      }

      if (typeof nP != 'undefined' && nP != oSound.lastValues.position) {
        oSound.lastValues.position = nP;
        sMethod = baseJSObject+"['"+sounds[i]+"']._whileplaying";
        // writeDebug('whileplaying(): '+nP+','+(newPeakData?lP+','+rP:null)+','+(newWaveformData?oSound.waveformDataArray:null)+','+(newEQData?oSound.eqDataArray:null));
        if (oSound.useNetstream != true) {
          ExternalInterface.call(sMethod,nP,(newPeakData?{leftPeak:lP,rightPeak:rP}:null),(newWaveformData?oSound.waveformDataArray:null),(newEQData?oSound.eqDataArray:null));
        } else {
	      ExternalInterface.call(sMethod,nP,null,null,null);
        }
        // if position changed, check for near-end
        if (oSound.didJustBeforeFinish != true && oSound.loaded == true && oSound.justBeforeFinishOffset > 0 && nD-nP <= oSound.justBeforeFinishOffset) {
          // fully-loaded, near end and haven't done this yet..
          sMethod = baseJSObject+"['"+sounds[i]+"']._onjustbeforefinish";
	      ExternalInterface.call(sMethod,(nD-nP));
          oSound.didJustBeforeFinish = true;
        }
      }
    }

  }

  public function onLoadError(oSound:Object):void {
	// something went wrong. 404, bad format etc.
    ExternalInterface.call(baseJSObject+"['"+oSound.sID+"']._onload",0);	
  }

  public function onLoad(e:Event):void {
    checkProgress(); // ensure progress stats are up-to-date
    var oSound:Object = e.target;
    if (!oSound.useNetstream) { // FLV must also have metadata
      oSound.loaded = true;
      // force duration update (doesn't seem to be always accurate)
      ExternalInterface.call(baseJSObject+"['"+oSound.sID+"']._whileloading",oSound.bytesLoaded,oSound.bytesTotal,oSound.length||oSound.duration);
      // TODO: Determine if loaded or failed - bSuccess?
      // ExternalInterface.call(baseJSObject+"['"+oSound.sID+"']._onload",bSuccess?1:0);
      ExternalInterface.call(baseJSObject+"['"+oSound.sID+"']._onload",1);
    }
  }

  public function onID3(e:Event):void {

    // --- NOTE: BUGGY (Flash 8 only? Haven't really checked 9 + 10.) ---
    // TODO: Investigate holes in ID3 parsing - for some reason, Album will be populated with Date if empty and date is provided. (?)
    // ID3V1 seem to parse OK, but "holes" / blanks in ID3V2 data seem to get messed up (eg. missing album gets filled with date.)
    // iTunes issues: onID3 was not called with a test MP3 encoded with iTunes 7.01, and what appeared to be valid ID3V2 data.
    // May be related to thumbnails for album art included in MP3 file by iTunes. See http://mabblog.com/blog/?p=33

	try {
	    var oSound:Object = e.target;

	    var id3Data:Array = [];
	    var id3Props:Array = [];
	    for (var prop:String in oSound.id3) {
	      id3Props.push(prop);
	      id3Data.push(oSound.id3[prop]);
	      // writeDebug('id3['+prop+']: '+oSound.id3[prop]);
	    }
	    ExternalInterface.call(baseJSObject+"['"+oSound.sID+"']._onid3",id3Props,id3Data);
	    // unhook own event handler, prevent second call (can fire twice as data is received - ID3V2 at beginning, ID3V1 at end.)
	    // Therefore if ID3V2 data is received, ID3V1 is ignored.
	    // soundObjects[oSound.sID].onID3 = null;
	} catch(e:Error) {
	  writeDebug('onID3(): Unable to get ID3 info for '+oSound.sID+'.');
	}
    oSound.removeEventListener(Event.ID3,onID3);
  }

  public function registerOnComplete(sID:String):void {
    if (soundObjects[sID] && soundObjects[sID].soundChannel) {
      soundObjects[sID].soundChannel.addEventListener(Event.SOUND_COMPLETE, function():void {
        this.didJustBeforeFinish = false; // reset
        if (soundObjects[sID]) {
          try {
            soundObjects[sID].start(0,1); // go back to 0
            soundObjects[sID].soundChannel.stop();
          } catch(e:Error) {
            writeDebug('Could not set position on '+sID+': '+e.toString());
          }
        }
        // checkProgress();
        ExternalInterface.call(baseJSObject+"['"+sID+"']._onfinish");
      });
    }
  }

  public function doSecurityError(oSound:SoundManager2_SMSound_AS3,e:SecurityErrorEvent):void {
    writeDebug('securityError: '+e.text);
    // when this happens, you don't have security rights on the server containing the FLV file
    // a crossdomain.xml file would fix the problem easily
  }
 
  public function doIOError(oSound:SoundManager2_SMSound_AS3,e:IOErrorEvent):void {
    // writeDebug('ioError: '+e.text);
    // call checkProgress()?
    ExternalInterface.call(baseJSObject+"['"+oSound.sID+"']._onload",0); // call onload, assume it failed.
    // there was a connection drop, a loss of internet connection, or something else wrong. 404 error too.
  }

  public function doAsyncError(oSound:SoundManager2_SMSound_AS3,e:AsyncErrorEvent):void {
    writeDebug('asyncError: '+e.text);
    // this is more related to streaming server from my experience, but you never know
  }

  public function doNetStatus(oSound:SoundManager2_SMSound_AS3,e:NetStatusEvent):void {
    // this will eventually let us know what is going on.. is the stream loading, empty, full, stopped?
    if (e.info.code != "NetStream.Buffer.Full" && e.info.code != "NetStream.Buffer.Empty" && e.info.code != "NetStream.Seek.Notify") {
      writeDebug('netStatusEvent: '+e.info.code);
    }

    if (e.info.code == "NetStream.Play.Stop") { // && !oSound.didFinish && oSound.loaded == true && nD == nP
      // finished playing
      // oSound.didFinish = true; // will be reset via JS callback
      oSound.didJustBeforeFinish = false; // reset
      writeDebug('calling onfinish for a sound');
      // writeDebug('sound, nD, nP: '+oSound.sID+', '+nD+', '+nP);
      // reset the sound
      oSound.ns.pause();
      oSound.ns.seek(0);
      // whileplaying()?
      ExternalInterface.call(baseJSObject+"['"+oSound.sID+"']._onfinish");
    }

    if (e.info.code == "NetStream.Play.FileStructureInvalid" || e.info.code == "NetStream.Play.FileStructureInvalid" || e.info.code == "NetStream.Play.StreamNotFound") {
	  this.onLoadError(oSound);
    }
  }

  public function addNetstreamEvents(oSound:SoundManager2_SMSound_AS3):void {
    oSound.ns.addEventListener(AsyncErrorEvent.ASYNC_ERROR, function(e:AsyncErrorEvent):void{doAsyncError(oSound,e)});
    oSound.ns.addEventListener(NetStatusEvent.NET_STATUS, function(e:NetStatusEvent):void{doNetStatus(oSound,e)});
    oSound.ns.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent):void{doIOError(oSound,e)});
    oSound.nc.addEventListener(NetStatusEvent.NET_STATUS, oSound.doNetStatus);
  }

  public function removeNetstreamEvents(oSound:SoundManager2_SMSound_AS3):void {
    oSound.ns.removeEventListener(AsyncErrorEvent.ASYNC_ERROR, function(e:AsyncErrorEvent):void{doAsyncError(oSound,e)});
    oSound.ns.removeEventListener(NetStatusEvent.NET_STATUS, function(e:NetStatusEvent):void{doNetStatus(oSound,e)});
    oSound.ns.removeEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent):void{doIOError(oSound,e)});
    oSound.nc.removeEventListener(NetStatusEvent.NET_STATUS, oSound.doNetStatus);
  }

  public function _setPosition(sID:String,nSecOffset:Number,isPaused:Boolean):void {
    var s:SoundManager2_SMSound_AS3 = soundObjects[sID];
    if (!s) return void;
    // writeDebug('_setPosition()');
    // stop current channel, start new one.
    if (s.lastValues) {
      s.lastValues.position = nSecOffset; // s.soundChannel.position;
    }
    if (s.useNetstream) {
	// writeDebug('setPosition: seeking to '+nSecOffset/1000);
      s.ns.seek(nSecOffset/1000);
      checkProgress(); // force UI update
    } else {
      if (s.soundChannel) {
        s.soundChannel.stop();
      }
      // writeDebug('setPosition: '+nSecOffset+', '+(s.lastValues.nLoops?s.lastValues.nLoops:1));
      try {
        s.start(nSecOffset,s.lastValues.nLoops||1); // start playing at new position
      } catch(e:Error) {
        writeDebug('Warning: Could not set position on '+sID+': '+e.toString());
      }
      checkProgress(); // force UI update
	  try {
	    registerOnComplete(sID);
	  } catch(e:Error) {
	    writeDebug('_setPosition(): Could not register onComplete');
	  }
      if (isPaused && s.soundChannel) {
        // writeDebug('_setPosition: stopping (paused) sound');
        // writeDebug('last position: '+s.lastValues.position+' vs '+s.soundChannel.position);
        s.soundChannel.stop();
      }
    }
  }

  public function _load(sID:String,sURL:String,bStream:Boolean,bAutoPlay:Boolean):void {
    writeDebug('_load()');
    if (typeof bAutoPlay == 'undefined') bAutoPlay = false;
    var s:SoundManager2_SMSound_AS3 = soundObjects[sID];
    if (!s) return void;
    var didRecreate:Boolean = false;
    if (s.didLoad == true) {
      // need to recreate sound
      didRecreate = true;
      writeDebug('recreating sound '+sID+' in order to load '+sURL);
      var ns:Object = new Object();
      ns.sID = s.sID;
      ns.justBeforeFinishOffset = s.justBeforeFinishOffset;
      ns.usePeakData = s.usePeakData;
      ns.useWaveformData = s.useWaveformData;
      ns.useEQData = s.useEQData;
      ns.useNetstream = s.useNetstream;
      ns.useVideo = s.useVideo;
      _destroySound(s.sID);
      _createSound(ns.sID,sURL,ns.justBeforeFinishOffset,ns.usePeakData,ns.useWaveformData,ns.useEQData,ns.useNetstream,ns.useVideo);
      s = soundObjects[sID];
      // writeDebug('Sound object replaced');
    }

    checkProgress();


    if (!s.didLoad) {
      try {
        s.addEventListener(Event.ID3, onID3);
        s.addEventListener(Event.COMPLETE, onLoad);
      } catch(e:Error) {
        writeDebug('_load(): could not assign ID3/complete event handlers');
      }
    }

    // s.addEventListener(ProgressEvent.PROGRESS, checkLoadProgress); // May be called often, potential CPU drain
    // s.addEventListener(Event.FINISH, onFinish);

    // s.loaded = true; // TODO: Investigate - Flash 9 non-FLV bug??
    // s.didLoad = true; // TODO: Investigate - bug?
    // if (didRecreate || s.sURL != sURL) {

    // don't try to load if same request already made
    s.sURL = sURL;

    if (s.useNetstream) {
      try {
	// s.ns.close();
	this.addNetstreamEvents(s);
	s.ns.play(sURL);
      } catch(e:Error) {
        writeDebug('_load(): error: '+e.toString());
      }
    } else {
      try {
        s.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent):void{doIOError(s,e)});
        s.loadSound(sURL,bStream);
      } catch(e:Error) {
        // oh well
        writeDebug('_load: Error loading '+sURL+'. Flash error detail: '+e.toString());
      }
    }

    s.didJustBeforeFinish = false;
    if (bAutoPlay != true) {
      // s.soundChannel.stop(); // prevent default auto-play behaviour
      // writeDebug('auto-play stopped');
    } else {
      // writeDebug('auto-play allowed');
      // s.start(0,1);
      // registerOnComplete(sID);
    }

  }

  public function _unload(sID:String,sURL:String):void {
    var s:SoundManager2_SMSound_AS3 = soundObjects[sID];
    if (!s) return void;
    try {
      removeEventListener(Event.ID3,onID3);
      removeEventListener(Event.COMPLETE, onLoad);
    } catch(e:Error) {
      writeDebug('_unload() warn: Could not remove ID3/complete events');
    }
    s.paused = false;
    if (s.soundChannel) {
      s.soundChannel.stop();
    }
    try {
      if (s.didLoad != true && !s.useNetstream) s.close(); // close stream only if still loading?
    } catch(e:Error) {
      // stream may already have closed if sound loaded, etc.
      writeDebug('sound._unload(): '+sID+' already unloaded?');
      // oh well
    }
    // destroy and recreate Flash sound object, try to reclaim memory
    // writeDebug('sound._unload(): recreating sound '+sID+' to free memory');
    if (s.useNetstream) {
	  // writeDebug('_unload(): closing netStream stuff');
      try {
	this.removeNetstreamEvents(s);
        s.ns.close();
        s.nc.close();
	// s.nc = null;
	//s.ns = null;
      } catch(e:Error) {
	// oh well
        writeDebug('_unload(): error during netConnection/netStream close');
      }
      if (s.useVideo) {
	writeDebug('_unload(): clearing video');
        s.oVideo.clear();
        // s.oVideo = null;
      }
    }
    var ns:Object = new Object();
    ns.sID = s.sID;
    ns.justBeforeFinishOffset = s.justBeforeFinishOffset;
    ns.usePeakData = s.usePeakData;
    ns.useWaveformData = s.useWaveformData;
    ns.useEQData = s.useEQData;
    ns.useNetstream = s.useNetstream;
    ns.useVideo = s.useVideo;
    _destroySound(s.sID);
    _createSound(ns.sID,sURL,ns.justBeforeFinishOffset,ns.usePeakData,ns.useWaveformData,ns.useEQData,ns.useNetstream,ns.useVideo);
  }

  public function _createSound(sID:String,sURL:String,justBeforeFinishOffset:int,usePeakData:Boolean,useWaveformData:Boolean,useEQData:Boolean,useNetstream:Boolean,useVideo:Boolean):void {
    soundObjects[sID] = new SoundManager2_SMSound_AS3(this,sID,sURL,usePeakData,useWaveformData,useEQData,useNetstream,useVideo);
    var s:SoundManager2_SMSound_AS3 = soundObjects[sID];
    if (!s) return void;
    // s.setVolume(100);
    s.didJustBeforeFinish = false;
    s.sID = sID;
    s.sURL = sURL;
    s.paused = false;
    s.loaded = false;
    s.justBeforeFinishOffset = justBeforeFinishOffset||0;
    s.lastValues = {
      bytes: 0,
      position: 0,
      nLoops: 1,
      leftPeak: 0,
      rightPeak: 0
    };
    if (!(sID in sounds)) sounds.push(sID);
    // sounds.push(sID);
  }

  public function _destroySound(sID:String):void {
    // for the power of garbage collection! .. er, Greyskull!
    var s:SoundManager2_SMSound_AS3 = (soundObjects[sID]||null);
    if (!s) return void;
    // try to unload the sound
    for (var i:int=0, j:int=sounds.length; i<j; i++) {
      if (sounds[i] == s) {
	    sounds.splice(i,1);
        continue;
      }
    }
    if (s.soundChannel) {
      s.soundChannel.stop();
    }
    this.stage.removeEventListener(Event.RESIZE, s.resizeHandler);
    // if is a movie, remove that as well.
    if (s.useNetstream) {
      // s.nc.client = null;
	  try {
	    this.removeNetstreamEvents(s);
	      // s.nc.removeEventListener(NetStatusEvent.NET_STATUS, s.doNetStatus);
	    } catch(e:Error) {
		  writeDebug('_destroySound(): Events already removed from netStream/netConnection?');
	    }

        if (s.useVideo) {
          try {
            this.removeChild(s.oVideo);
          } catch(e:Error) {
	    writeDebug('_destoySound(): could not remove video?');
        }
      }
      if (s.didLoad) {
        try {
          s.ns.close();
	  	  s.nc.close();
        } catch(e:Error) {
	      // oh well
          writeDebug('_destroySound(): error during netConnection/netStream close and null');
	  	}
      }
    }
    s = null;
    soundObjects[sID] = null;
    delete soundObjects[sID];
  }

  public function _stop(sID:String,bStopAll:Boolean):void {
    // stop this particular instance (or "all", based on parameter)
    if (bStopAll) {
	  SoundMixer.stopAll();
      // ExternalInterface.call('alert','Flash: need _stop for all sounds');
      // SoundManager2_AS3.display.stage.stop(); // _root.stop();
      // this.soundChannel.stop();
      // soundMixer.stop();
    } else {
	  var s:SoundManager2_SMSound_AS3 = soundObjects[sID];
	  if (!s) return void;
      if (s.useNetstream) {
        s.ns.pause();
        if (s.oVideo) {
          s.oVideo.visible = false;
        }
      } else {
        s.soundChannel.stop();
      }
      s.paused = false;
      s.didJustBeforeFinish = false;
    }
  }

  public function _start(sID:String,nLoops:int,nMsecOffset:int):void {
    var s:SoundManager2_SMSound_AS3 = soundObjects[sID];
    if (!s) return void;
    s.lastValues.paused = false; // reset pause if applicable
    s.lastValues.nLoops = (nLoops||1);
    s.lastValues.position = nMsecOffset;
    try {
      s.start(nMsecOffset,nLoops);
    } catch(e:Error) {
      writeDebug('Could not start '+sID+': '+e.toString());
    }
    try {
      registerOnComplete(sID);
    } catch(e:Error) {
      writeDebug('_start(): registerOnComplete failed');
    }
  }

  public function _pause(sID:String):void {
    // writeDebug('_pause()');
    var s:SoundManager2_SMSound_AS3 = soundObjects[sID];
    if (!s) return void;
    // writeDebug('s.paused: '+s.paused);
    if (!s.paused) {
      // reference current position, stop sound
      s.paused = true; 
      // writeDebug('_pause(): position: '+s.lastValues.position);
      if (s.useNetstream) {
	    s.lastValues.position = s.ns.time;
        s.ns.pause();
      } else {
        if (s.soundChannel) {
	      s.lastValues.position = s.soundChannel.position;
          s.soundChannel.stop();
        }
      }
    } else {
      // resume playing from last position
      // writeDebug('resuming - playing at '+s.lastValues.position+', '+s.lastValues.nLoops+' times');
      s.paused = false;
      if (s.useNetstream) {
        s.ns.resume();
      } else {
        s.start(s.lastValues.position,s.lastValues.nLoops);
      }
      try {
        registerOnComplete(sID);
      } catch(e:Error) {
        writeDebug('_pause(): registerOnComplete() failed');
      }
    }
  }

  public function _setPan(sID:String,nPan:Number):void {
    soundObjects[sID].setPan(nPan);
  }
 
  public function _setVolume(sID:String,nVol:Number):void {
    // writeDebug('_setVolume: '+nVol);
    soundObjects[sID].setVolume(nVol);
  }

  public function _setPolling(bPolling:Boolean):void {
    pollingEnabled = bPolling;
    if (timer == null && pollingEnabled) {
      writeDebug('Enabling polling');
      timer = new Timer(timerInterval,0);
      timer.addEventListener(TimerEvent.TIMER, function():void{checkProgress();}); // direct reference eg. checkProgress doesn't work? .. odd.
      timer.start();
    } else if (timer && !pollingEnabled) {
      writeDebug('Disabling polling');
      // flash.utils.clearInterval(timer);
      timer.reset();
    }
  }

  // XML handler stuff

  public function _loadFromXML(sURL:String):void {
    var loader:URLLoader = new URLLoader();
    loader.addEventListener(Event.COMPLETE, parseXML);
    writeDebug('Attempting to load XML: '+sURL);
    try {
      loader.load(new URLRequest(sURL));    
    } catch(e:Error) {
      writeDebug('Error loading XML: '+e.toString());
    }
  }

  public function parseXML(e:Event):void {
    try {
      var oXML:XMLDocument = new XMLDocument();
      oXML.ignoreWhite = true;
      oXML.parseXML(e.target.data);
      var xmlRoot:XMLNode = oXML.firstChild;
      var xmlAttr:Object = xmlRoot.attributes;
      var oOptions:Object = {};
      var i:int = 0;
      var j:int = 0;
      for (i=0,j=xmlRoot.childNodes.length; i<j; i++) {
        xmlAttr = xmlRoot.childNodes[i].attributes;
        oOptions = {
          id : xmlAttr.id,
          url : xmlRoot.attributes.baseHref+xmlAttr.href,
          stream : xmlAttr.stream
        }
        ExternalInterface.call(baseJSController+".createSound",oOptions);
      }
    } catch(e:Error) {
      writeDebug('Error parsing XML: '+e.toString());
    }
  }

  // -----------------------------------
  // end methods

}

// package
}
