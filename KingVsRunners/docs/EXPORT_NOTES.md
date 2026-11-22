# Export notes

`src/` was exported from the place file (`.rbxl`) with the scripts in [`tools/`](../tools). The rules below decide what is left out.

## Excluded scripts

### 외부 코드: Roblox default Animate (6)
- `ReplicatedStorage/exhausted Rig/Animate`
- `ServerStorage/TaggerBot/King npc2/Animate`
- `Workspace/LobbyTrainingDummy/Animate`
- `Workspace/LobbyTrainingDummy_B/Animate`
- `Workspace/LobbyTrainingDummy_C/Animate`
- `Workspace/LobbyTrainingDummy_D/Animate`

### 꺼져 있는 테스트·진단 스크립트 (17)
- `ServerScriptService/BotPerfTest`
- `ServerScriptService/DemonSpearTestHandler`
- `ServerScriptService/HpGainDiag`
- `ServerScriptService/TestLauncherSystem`
- `ServerScriptService/_FrostDragonTest`
- `ServerScriptService/_KatanaRuntimeTuner`
- `ServerScriptService/_LagProbeServer`
- `ServerScriptService/_RareChestTuner`
- `ServerScriptService/_SkinAlignHarness`
- `ServerScriptService/_SkinRotTunerServer`
- `ServerScriptService/_TaggerDummyRespawner`
- `ServerScriptService/_TestForceRunner`
- `ServerScriptService/_TestRigBoot`
- `ServerScriptService/_WalkSpeedProbe`
- `StarterPlayer/StarterPlayerScripts/_FrostDragonClientDiag`
- `StarterPlayer/StarterPlayerScripts/_LagProbeClient`
- `StarterPlayer/StarterPlayerScripts/__SoundScan`

### 빈 스크립트 (2)
- `ServerScriptService/DiveServer`
- `StarterPlayer/StarterPlayerScripts/SfxGroupBinder`

### 외부 코드: Luckymaxer (toolbox) (4)
- `ServerStorage/RunnerItem/ClassicSword/MouseIcon`
- `ServerStorage/RunnerItem/Ice Bow/MouseIcon`
- `ServerStorage/RunnerItem/Ice Bow/Script/DeathEffect`
- `ServerStorage/RunnerItem/Ice Bow/Script/ParticleScript`

### 백업 사본 (19)
- `ServerStorage/FirePressureSystem_LAVA_BACKUP`
- `ServerStorage/RunnerItem/Ice Bow/LocalScript_OLD_DISABLED`
- `ServerStorage/_Archive/Anim_Rig/Animate`
- `ServerStorage/_Archive/Test_Dummy/KING_shot/Animate`
- `ServerStorage/_Archive/Test_Dummy/KING_shot/_DamageSensor`
- `ServerStorage/_Archive/Test_Dummy/RUNNER_shot_1/Animate`
- `ServerStorage/_Archive/Test_Dummy/RUNNER_shot_2/Animate`
- `ServerStorage/_Archive/Test_Dummy/RUNNER_shot_3/Animate`
- `ServerStorage/_Archive/Test_Dummy/RUNNER_shot_4/Animate`
- `ServerStorage/_Archive/_GauntletBackup_PreSetUlt/ChargeClient`
- `ServerStorage/_Archive/_GauntletBackup_PreSetUlt/GauntletScript`
- `ServerStorage/_Archive/_GauntletBackup_PreWallPenalty/ChargeClient`
- `ServerStorage/_Archive/_GauntletBackup_PreWallPenalty/GauntletScript`
- `ServerStorage/_Archive/_TestForceRunnerGui/ForceRunnerClient`
- `ServerStorage/_Backup_OldLobby/Island/DisplayItemNoob/DisplayRotation`
- `ServerStorage/_TestRigs/runnerdummy2/Animate`
- `ServerStorage/_TestRigs/runnerdummy2_2/Animate`
- `ServerStorage/_TestRigs/taggerdummy/Animate`
- `ServerStorage/_TestRigs/taggerdummy/_DamageSensor`

### 외부 코드: Quenty (toolbox) (8)
- `ServerStorage/ArmorTemplates/Military Vest/Handle/BodyFrontAttachment/LightConfig`
- `ServerStorage/ArmorTemplates/Military Vest/Handle/BodyFrontAttachment/LightConfig/Type`
- `ServerStorage/Famer2/Head/qPerfectionWeld`
- `ServerStorage/Famer2/Left Arm/qPerfectionWeld`
- `ServerStorage/Famer2/Right Arm/qPerfectionWeld`
- `ServerStorage/Famer2/Torso/qPerfectionWeld`
- `ServerStorage/RunnerItem/Gas Grenade/Handle/qPerfectionWeld`
- `ServerStorage/RunnerItem/ODM Gear/ODM_Belt/Handle/Model/qPerfectionWeld`

### 외부 코드: ActualFreedom flag (toolbox) (1)
- `ReplicatedStorage/revival flag/AnimatedFlag/Animate`

### 외부 코드: Toolbox diamond sword (2)
- `ServerStorage/RunnerItem/DiamondBladeSword/SwordMain/DiamondRainScript`
- `ServerStorage/RunnerItem/DiamondBladeSword/SwordMain/DiamondRainScript/BulletScript`

### 외부 코드: Toolbox AC-130 prop (8)
- `ServerStorage/AC-130/Model/AC130/Bodykit/Bodykit/Propellers/Part/SurfaceGui/ImageLabel/GUIRotation script`
- `ServerStorage/AC-130/Model/AC130/Bodykit/Bodykit/Propellers/Part/SurfaceGui/ImageLabel/GUIRotation script`
- `ServerStorage/AC-130/Model/AC130/Bodykit/Bodykit/Propellers/Part/SurfaceGui/ImageLabel/GUIRotation script`
- `ServerStorage/AC-130/Model/AC130/Bodykit/Bodykit/Propellers/Part/SurfaceGui/ImageLabel/GUIRotation script`
- `ServerStorage/AC-130/Model/AC130/Bodykit/Bodykit/Propellers/Part/SurfaceGui/ImageLabel/GUIRotation script`
- `ServerStorage/AC-130/Model/AC130/Bodykit/Bodykit/Propellers/Part/SurfaceGui/ImageLabel/GUIRotation script`
- `ServerStorage/AC-130/Model/AC130/Bodykit/Bodykit/Propellers/Part/SurfaceGui/ImageLabel/GUIRotation script`
- `ServerStorage/AC-130/Model/AC130/Bodykit/Bodykit/Propellers/Part/SurfaceGui/ImageLabel/GUIRotation script`

## Merged duplicates

Skin variants and preview copies that are byte-for-byte identical are kept once, at the first path below.

- `ServerStorage/RunnerItem/ODM Gear/ODM_Belt/Handle/Model/Handle/Script` ← 1 identical copies
  - `ServerStorage/RunnerItem/ODM Gear/ODM_Belt/Handle/Model/Handle/Script`
- `ServerStorage/TaggerItem/BeachBall/_SplashSoundLoop` ← 3 identical copies
  - `ReplicatedStorage/SkinPreviews/BeachBall/_SplashSoundLoop`
  - `ReplicatedStorage/SkinPreviews/SummerNoob/_CollisionCore/_SplashSoundLoop`
  - `ServerStorage/TaggerItem/SummerNoob/_CollisionCore/_SplashSoundLoop`
- `ServerStorage/TaggerItem/BlueBearTrap/HitBox/CatchPlayer` ← 30 identical copies
  - `ReplicatedStorage/SkinPreviews/BlueBearTrap/HitBox/CatchPlayer`
  - `ReplicatedStorage/SkinPreviews/BronzeBearTrap/HitBox/CatchPlayer`
  - `ReplicatedStorage/SkinPreviews/CobaltBearTrap/HitBox/CatchPlayer`
  - `ReplicatedStorage/SkinPreviews/CrimsonBearTrap/HitBox/CatchPlayer`
  - `ReplicatedStorage/SkinPreviews/DeepPurpleBearTrap/HitBox/CatchPlayer`
  - `ReplicatedStorage/SkinPreviews/EmeraldBearTrap/HitBox/CatchPlayer`
  - `ReplicatedStorage/SkinPreviews/GoldBearTrap/HitBox/CatchPlayer`
  - `ReplicatedStorage/SkinPreviews/GreenBearTrap/HitBox/CatchPlayer`
  - `ReplicatedStorage/SkinPreviews/ObsidianBearTrap/HitBox/CatchPlayer`
  - `ReplicatedStorage/SkinPreviews/OrangeBearTrap/HitBox/CatchPlayer`
  - `ReplicatedStorage/SkinPreviews/RainbowBearTrap/HitBox/CatchPlayer`
  - `ReplicatedStorage/SkinPreviews/RedBearTrap/HitBox/CatchPlayer`
  - `ReplicatedStorage/SkinPreviews/ToxicBearTrap/HitBox/CatchPlayer`
  - `ReplicatedStorage/SkinPreviews/VioletBearTrap/HitBox/CatchPlayer`
  - `ReplicatedStorage/SkinPreviews/YellowBearTrap/HitBox/CatchPlayer`
  - `ServerStorage/TaggerItem/BronzeBearTrap/HitBox/CatchPlayer`
  - `ServerStorage/TaggerItem/CobaltBearTrap/HitBox/CatchPlayer`
  - `ServerStorage/TaggerItem/CrimsonBearTrap/HitBox/CatchPlayer`
  - `ServerStorage/TaggerItem/DeepPurpleBearTrap/HitBox/CatchPlayer`
  - `ServerStorage/TaggerItem/EmeraldBearTrap/HitBox/CatchPlayer`
  - `ServerStorage/TaggerItem/GoldBearTrap/HitBox/CatchPlayer`
  - `ServerStorage/TaggerItem/GreenBearTrap/HitBox/CatchPlayer`
  - `ServerStorage/TaggerItem/ObsidianBearTrap/HitBox/CatchPlayer`
  - `ServerStorage/TaggerItem/OrangeBearTrap/HitBox/CatchPlayer`
  - `ServerStorage/TaggerItem/RainbowBearTrap/HitBox/CatchPlayer`
  - `ServerStorage/TaggerItem/RedBearTrap/HitBox/CatchPlayer`
  - `ServerStorage/TaggerItem/ToxicBearTrap/HitBox/CatchPlayer`
  - `ServerStorage/TaggerItem/VioletBearTrap/HitBox/CatchPlayer`
  - `ServerStorage/TaggerItem/YellowBearTrap/HitBox/CatchPlayer`
  - `ServerStorage/TaggerItem/bear_trap/HitBox/CatchPlayer`
- `ServerStorage/TaggerItem/BlueNoob/_NoobZigzag` ← 31 identical copies
  - `ReplicatedStorage/SkinPreviews/BlueNoob/_NoobZigzag`
  - `ReplicatedStorage/SkinPreviews/GlitchNoob/_NoobZigzag`
  - `ReplicatedStorage/SkinPreviews/GoldNeonNoob/_NoobZigzag`
  - `ReplicatedStorage/SkinPreviews/GreenNoob/_NoobZigzag`
  - `ReplicatedStorage/SkinPreviews/IceNoob/_NoobZigzag`
  - `ReplicatedStorage/SkinPreviews/IndigoNoob/_NoobZigzag`
  - `ReplicatedStorage/SkinPreviews/KingNoob/_NoobZigzag`
  - `ReplicatedStorage/SkinPreviews/LavaNoob/_NoobZigzag`
  - `ReplicatedStorage/SkinPreviews/OrangeNoob/_NoobZigzag`
  - `ReplicatedStorage/SkinPreviews/RainbowNoob/_NoobZigzag`
  - `ReplicatedStorage/SkinPreviews/SoldierNoob/_NoobZigzag`
  - `ReplicatedStorage/SkinPreviews/SuitNoob/_NoobZigzag`
  - `ReplicatedStorage/SkinPreviews/SummerNoob/_NoobZigzag`
  - `ReplicatedStorage/SkinPreviews/VioletNoob/_NoobZigzag`
  - `ReplicatedStorage/SkinPreviews/YellowNoob/_NoobZigzag`
  - `ReplicatedStorage/SkinPreviews/ZombieNoob/_NoobZigzag`
  - `ServerStorage/TaggerItem/GlitchNoob/_NoobZigzag`
  - `ServerStorage/TaggerItem/GoldNeonNoob/_NoobZigzag`
  - `ServerStorage/TaggerItem/GreenNoob/_NoobZigzag`
  - `ServerStorage/TaggerItem/IceNoob/_NoobZigzag`
  - `ServerStorage/TaggerItem/IndigoNoob/_NoobZigzag`
  - `ServerStorage/TaggerItem/KingNoob/_NoobZigzag`
  - `ServerStorage/TaggerItem/LavaNoob/_NoobZigzag`
  - `ServerStorage/TaggerItem/OrangeNoob/_NoobZigzag`
  - `ServerStorage/TaggerItem/RainbowNoob/_NoobZigzag`
  - `ServerStorage/TaggerItem/SoldierNoob/_NoobZigzag`
  - `ServerStorage/TaggerItem/SuitNoob/_NoobZigzag`
  - `ServerStorage/TaggerItem/SummerNoob/_NoobZigzag`
  - `ServerStorage/TaggerItem/VioletNoob/_NoobZigzag`
  - `ServerStorage/TaggerItem/YellowNoob/_NoobZigzag`
  - `ServerStorage/TaggerItem/ZombieNoob/_NoobZigzag`
- `ServerStorage/TaggerItem/DemonFlameStone/_DemonSoundLoop` ← 1 identical copies
  - `ReplicatedStorage/SkinPreviews/DemonFlameStone/_DemonSoundLoop`
- `ServerStorage/TaggerItem/RainbowBearTrap/Open/_RainbowCycle` ← 5 identical copies
  - `ReplicatedStorage/SkinPreviews/RainbowBearTrap/Open/_RainbowCycle`
  - `ReplicatedStorage/SkinPreviews/RainbowSpear/_RainbowCycle`
  - `ReplicatedStorage/SkinPreviews/RainbowStone/_RainbowCycle`
  - `ServerStorage/TaggerItem/RainbowSpear/_RainbowCycle`
  - `ServerStorage/TaggerItem/RainbowStone/_RainbowCycle`
- `ServerStorage/TaggerItem/RainbowNoob/_RainbowCycle` ← 1 identical copies
  - `ReplicatedStorage/SkinPreviews/RainbowNoob/_RainbowCycle`
- `ServerStorage/TaggerItem/SummerNoob/_CollisionCore/_CheerSoundLoop` ← 1 identical copies
  - `ReplicatedStorage/SkinPreviews/SummerNoob/_CollisionCore/_CheerSoundLoop`
- `Workspace/LB_KingWins/First Place Avatar/PlayAnimationInRig` ← 1 identical copies
  - `Workspace/LB_Kingslayer/First Place Avatar/PlayAnimationInRig`
- `Workspace/LobbyTrainingDummy/_DamageSensor` ← 3 identical copies
  - `Workspace/LobbyTrainingDummy_B/_DamageSensor`
  - `Workspace/LobbyTrainingDummy_C/_DamageSensor`
  - `Workspace/LobbyTrainingDummy_D/_DamageSensor`
