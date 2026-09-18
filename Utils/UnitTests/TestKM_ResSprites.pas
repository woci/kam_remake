unit TestKM_ResSprites;
{$I ..\..\KaM_Remake.inc}
interface
uses
  TestFramework, Windows, SysUtils, Classes, IOUtils,
  KM_CommonTypes, KM_ResTypes, KM_ResSprites, KM_ResSpritesEdit;

type
  // HD rendering support in the sprite packs (Docs/HD_Rendering_Plan.md):
  // per-sprite scale, overload file name parsing, atlas edge padding, PNG scale derivation, RXX3/RXA3 round trips
  TestKMResSprites = class(TTestCase)
  strict private
    fDir: string;
    procedure WriteTestPng(const aName: string; aW, aH: Integer; aColor: Cardinal);
    procedure WritePivotTxt(const aName: string; aX, aY: Integer);
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestScaleAccessors;
    procedure TestParseOverloadFileName;
    procedure TestExtendSpriteEdges;
    procedure TestAddImageScaleDerivation;
    procedure TestAddImageExplicitScale;
    procedure TestRxx3RoundTrip;
    procedure TestRxx2StillLoads;
    procedure TestRxa3RoundTrip;
  end;


implementation
uses
  KM_Defaults, KM_Log, KM_IoPNG;


procedure TestKMResSprites.SetUp;
begin
  fDir := IncludeTrailingPathDelimiter(TPath.Combine(TPath.GetTempPath, 'KaM_UnitTests_' + IntToStr(GetCurrentProcessId)));
  ForceDirectories(fDir);
  ExeDir := fDir;
  // The sprite code logs; keep the log outside fDir so TearDown can delete the folder while the log stays open
  if gLog = nil then
    gLog := TKMLog.Create(TPath.Combine(TPath.GetTempPath, 'KaM_UnitTests.log'));
end;


procedure TestKMResSprites.TearDown;
begin
  TDirectory.Delete(fDir, True);
end;


procedure TestKMResSprites.WriteTestPng(const aName: string; aW, aH: Integer; aColor: Cardinal);
var
  data: TKMCardinalArray;
  I: Integer;
begin
  SetLength(data, aW * aH);
  for I := 0 to aW * aH - 1 do
    data[I] := aColor;
  SaveToPng(aW, aH, data, fDir + aName);
end;


procedure TestKMResSprites.WritePivotTxt(const aName: string; aX, aY: Integer);
begin
  TFile.WriteAllText(fDir + aName, IntToStr(aX) + sLineBreak + IntToStr(aY) + sLineBreak);
end;


procedure TestKMResSprites.TestScaleAccessors;
var
  rx: TRXData;
begin
  // No Scale array allocated at all (packs that never saw an HD overload)
  SetLength(rx.Size, 3);
  SetLength(rx.Pivot, 3);
  rx.Size[1].X := 40; rx.Size[1].Y := 80;
  rx.Pivot[1].X := -20; rx.Pivot[1].Y := -60;
  CheckEquals(1, rx.ScaleOf(1), 'unallocated Scale defaults to 1');
  CheckEquals(40, rx.SizeXf(1), 0.001);
  CheckEquals(-60, rx.PivotYf(1), 0.001);

  SetLength(rx.Scale, 3);
  rx.Scale[1] := 4;
  rx.Scale[2] := 0; // zero-filled by SetLength, must still read as 1
  CheckEquals(4, rx.ScaleOf(1));
  CheckEquals(10, rx.SizeXf(1), 0.001, 'logical size = px / scale');
  CheckEquals(20, rx.SizeYf(1), 0.001);
  CheckEquals(-5, rx.PivotXf(1), 0.001, 'logical pivot = px / scale');
  CheckEquals(-15, rx.PivotYf(1), 0.001);
  CheckEquals(1, rx.ScaleOf(2), 'zero scale reads as 1');
  CheckEquals(1, rx.ScaleOf(99), 'out of range reads as 1');
  CheckEquals(1, rx.ScaleOf(-1), 'negative id reads as 1');
end;


procedure TestKMResSprites.TestParseOverloadFileName;
var
  id, scale: Integer;
begin
  Check(ParseOverloadFileName('5_1234.png', id, scale));
  CheckEquals(1234, id);
  CheckEquals(0, scale, 'no marker -> 0 (derive)');

  Check(ParseOverloadFileName('5_1234@4x.png', id, scale));
  CheckEquals(1234, id);
  CheckEquals(4, scale);

  Check(ParseOverloadFileName('5_1234@2X.png', id, scale), 'upper case X accepted');
  CheckEquals(2, scale);

  Check(ParseOverloadFileName('sub\folder\5_12.png', id, scale), 'path and short id');
  CheckEquals(12, id);

  Check(ParseOverloadFileName('3_65535@4x.png', id, scale));
  CheckEquals(65535, id);

  // Companion files are never sprites
  Check(not ParseOverloadFileName('5_1234a.png', id, scale), 'team colour mask');
  Check(not ParseOverloadFileName('5_1234m.png', id, scale), 'plain mask');
  Check(not ParseOverloadFileName('5_1234@4xa.png', id, scale), 'HD team colour mask');
  Check(not ParseOverloadFileName('5_1234@4xm.png', id, scale), 'HD plain mask');

  // Malformed markers
  Check(not ParseOverloadFileName('5_1234@x.png', id, scale), 'missing number');
  Check(not ParseOverloadFileName('5_1234@0x.png', id, scale), 'zero scale');
  Check(not ParseOverloadFileName('5_1234@4.png', id, scale), 'missing x');
  Check(not ParseOverloadFileName('5_.png', id, scale), 'no id');
  Check(not ParseOverloadFileName('5_12_34.png', id, scale), 'not digits');
end;


procedure TestKMResSprites.TestExtendSpriteEdges;
const
  W = 8;
var
  atlas: TKMCardinalArray;
  I: Integer;
begin
  SetLength(atlas, W * W);
  // 2x2 sprite at (3,3): TL=1 TR=2 BL=3 BR=4
  atlas[3 * W + 3] := 1; atlas[3 * W + 4] := 2;
  atlas[4 * W + 3] := 3; atlas[4 * W + 4] := 4;

  ExtendSpriteEdges(atlas, W, 3, 3, 2, 2, 2);

  // Rows above / below replicate the edge row
  CheckEquals(1, atlas[2 * W + 3]); CheckEquals(2, atlas[2 * W + 4]);
  CheckEquals(1, atlas[1 * W + 3]); CheckEquals(2, atlas[1 * W + 4]);
  CheckEquals(3, atlas[5 * W + 3]); CheckEquals(4, atlas[5 * W + 4]);
  CheckEquals(3, atlas[6 * W + 3]); CheckEquals(4, atlas[6 * W + 4]);
  // Columns left / right
  CheckEquals(1, atlas[3 * W + 2]); CheckEquals(1, atlas[3 * W + 1]);
  CheckEquals(2, atlas[3 * W + 5]); CheckEquals(2, atlas[3 * W + 6]);
  // Corners are filled too (this is what a 1px-only extension used to miss)
  CheckEquals(1, atlas[1 * W + 1], 'top-left corner');
  CheckEquals(2, atlas[1 * W + 6], 'top-right corner');
  CheckEquals(3, atlas[6 * W + 1], 'bottom-left corner');
  CheckEquals(4, atlas[6 * W + 6], 'bottom-right corner');
  // Nothing outside the pad ring is touched
  for I := 0 to W - 1 do
  begin
    CheckEquals(0, atlas[0 * W + I], 'row 0 untouched');
    CheckEquals(0, atlas[7 * W + I], 'row 7 untouched');
    CheckEquals(0, atlas[I * W + 0], 'col 0 untouched');
    CheckEquals(0, atlas[I * W + 7], 'col 7 untouched');
  end;
  // Sprite itself intact
  CheckEquals(1, atlas[3 * W + 3]); CheckEquals(4, atlas[4 * W + 4]);
end;


procedure TestKMResSprites.TestAddImageScaleDerivation;
var
  pack: TKMSpritePack;
  rx: TRXData;
begin
  pack := TKMSpritePack.Create(rxTrees, True);
  try
    // 1. Brand-new sprite: no original, scale 1, pivot from txt
    WriteTestPng('1_0001.png', 10, 20, $FF336699);
    WritePivotTxt('1_0001.txt', -5, -7);
    pack.AddImage(fDir, '1_0001.png', 1);
    rx := pack.RXData;
    CheckEquals(1, rx.ScaleOf(1));
    CheckEquals(10, rx.Size[1].X); CheckEquals(20, rx.Size[1].Y);
    CheckEquals(-5, rx.Pivot[1].X); CheckEquals(-7, rx.Pivot[1].Y);
    CheckEquals($FF336699, rx.RGBA[1, 0], 'PNG pixel round trip (row-based reader)');

    // 2. Uniform 4x replacement: scale derived, pivot rescaled to texels
    DeleteFile(fDir + '1_0001.txt');
    WriteTestPng('1_0001.png', 40, 80, $FF112233);
    pack.AddImage(fDir, '1_0001.png', 1);
    rx := pack.RXData;
    CheckEquals(4, rx.ScaleOf(1), 'derived scale');
    CheckEquals(40, rx.Size[1].X, 'Size stays in texels');
    CheckEquals(-20, rx.Pivot[1].X, 'pivot rescaled to texels');
    CheckEquals(-28, rx.Pivot[1].Y);
    CheckEquals(10, rx.SizeXf(1), 0.001, 'logical size unchanged');
    CheckEquals(-5, rx.PivotXf(1), 0.001, 'logical pivot unchanged');

    // 3. Replacing an HD sprite with another 2x file of the same logical size: derived against the logical size, not the previous texels
    WriteTestPng('1_0001.png', 20, 40, $FF445566);
    pack.AddImage(fDir, '1_0001.png', 1);
    rx := pack.RXData;
    CheckEquals(2, rx.ScaleOf(1), 'scale relative to logical size');
    CheckEquals(-10, rx.Pivot[1].X);

    // 4. Non-uniform size: not an HD multiple, scale falls back to 1 (object changes size, as before HD support)
    WriteTestPng('1_0001.png', 40, 60, $FF778899);
    pack.AddImage(fDir, '1_0001.png', 1);
    rx := pack.RXData;
    CheckEquals(1, rx.ScaleOf(1), 'non-uniform -> scale 1');
    CheckEquals(-5, rx.Pivot[1].X, 'pivot back to logical pixels');
  finally
    pack.Free;
  end;
end;


procedure TestKMResSprites.TestAddImageExplicitScale;
var
  pack: TKMSpritePack;
  rx: TRXData;
begin
  pack := TKMSpritePack.Create(rxTrees, True);
  try
    // New sprite with no original: only an explicit marker can make it HD
    WriteTestPng('1_0007@4x.png', 40, 80, $FFAABBCC);
    WritePivotTxt('1_0007@4x.txt', -20, -28); // pivot in the PNG's own pixels
    pack.AddImage(fDir, '1_0007@4x.png', 7, False, 4);
    rx := pack.RXData;
    CheckEquals(4, rx.ScaleOf(7));
    CheckEquals(10, rx.SizeXf(7), 0.001);
    CheckEquals(-5, rx.PivotXf(7), 0.001);

    // Explicit marker wins over derivation, even for a non-uniform file
    WriteTestPng('1_0007@2x.png', 30, 80, $FFAABBCC);
    pack.AddImage(fDir, '1_0007@2x.png', 7, False, 2);
    rx := pack.RXData;
    CheckEquals(2, rx.ScaleOf(7), 'explicit scale overrides derivation');
  finally
    pack.Free;
  end;
end;


procedure TestKMResSprites.TestRxx3RoundTrip;
var
  edit: TKMSpritePackEdit;
  pack: TKMSpritePack;
  rx: TRXData;
begin
  edit := TKMSpritePackEdit.Create(rxTrees, nil);
  try
    WriteTestPng('1_0001.png', 10, 20, $FF010203);
    WritePivotTxt('1_0001.txt', -5, -7);
    edit.AddImage(fDir, '1_0001.png', 1);
    WriteTestPng('1_0002@4x.png', 40, 80, $FF040506);
    WritePivotTxt('1_0002@4x.txt', -20, -28);
    edit.AddImage(fDir, '1_0002@4x.png', 2, False, 4);
    edit.SaveToRXXFile(fDir + 'test.rxx', rxxThree);
  finally
    edit.Free;
  end;

  pack := TKMSpritePack.Create(rxTrees, True);
  try
    pack.LoadFromRXXFile(fDir + 'test.rxx');
    rx := pack.RXData;
    CheckEquals(2, rx.Count);
    CheckEquals(1, rx.Flag[1]); CheckEquals(1, rx.Flag[2]);
    CheckEquals(1, rx.ScaleOf(1), 'SD sprite scale');
    CheckEquals(4, rx.ScaleOf(2), 'HD sprite scale survives RXX3');
    CheckEquals(40, rx.Size[2].X); CheckEquals(80, rx.Size[2].Y);
    CheckEquals(-20, rx.Pivot[2].X); CheckEquals(-28, rx.Pivot[2].Y);
    CheckEquals($FF040506, rx.RGBA[2, 0]);
    CheckEquals($FF010203, rx.RGBA[1, 10 * 20 - 1]);
  finally
    pack.Free;
  end;
end;


procedure TestKMResSprites.TestRxx2StillLoads;
var
  edit: TKMSpritePackEdit;
  pack: TKMSpritePack;
  rx: TRXData;
begin
  // The older format has no Scale field: everything must load as scale 1 and the pixel data must line up
  edit := TKMSpritePackEdit.Create(rxTrees, nil);
  try
    WriteTestPng('1_0001@4x.png', 40, 80, $FF040506);
    edit.AddImage(fDir, '1_0001@4x.png', 1, False, 4);
    edit.SaveToRXXFile(fDir + 'test2.rxx', rxxTwo);
  finally
    edit.Free;
  end;

  pack := TKMSpritePack.Create(rxTrees, True);
  try
    pack.LoadFromRXXFile(fDir + 'test2.rxx');
    rx := pack.RXData;
    CheckEquals(1, rx.Count);
    CheckEquals(1, rx.ScaleOf(1), 'RXX2 carries no scale');
    CheckEquals(40, rx.Size[1].X);
    CheckEquals($FF040506, rx.RGBA[1, 40 * 80 - 1], 'pixel data not shifted by a phantom scale field');
  finally
    pack.Free;
  end;
end;


procedure TestKMResSprites.TestRxa3RoundTrip;
var
  edit: TKMSpritePackEdit;
  pack: TKMSpritePack;
  rx: TRXData;
  I, sdAtlases, hdAtlases: Integer;
begin
  edit := TKMSpritePackEdit.Create(rxTrees, nil);
  try
    WriteTestPng('1_0001.png', 10, 20, $FF010203);
    edit.AddImage(fDir, '1_0001.png', 1);
    WriteTestPng('1_0002@4x.png', 40, 80, $FF040506);
    edit.AddImage(fDir, '1_0002@4x.png', 2, False, 4);
    // Bin-packs into atlases (SD and HD separately) without touching OpenGL
    edit.SaveToRXAFile(fDir + 'test.rxa', rxxThree);
  finally
    edit.Free;
  end;

  pack := TKMSpritePack.Create(rxTrees, True);
  try
    pack.LoadFromRXAFile(fDir + 'test.rxa');
    rx := pack.RXData;
    CheckEquals(2, rx.Count);
    CheckEquals(1, rx.ScaleOf(1));
    CheckEquals(4, rx.ScaleOf(2), 'HD sprite scale survives RXA3');

    sdAtlases := 0;
    hdAtlases := 0;
    for I := Low(pack.Atlases[saBase]) to High(pack.Atlases[saBase]) do
      if pack.Atlases[saBase, I].HD then
        Inc(hdAtlases)
      else
        Inc(sdAtlases);
    CheckEquals(1, sdAtlases, 'one SD base atlas');
    CheckEquals(1, hdAtlases, 'one HD base atlas (HD flag survives RXA3)');

    // The HD atlas holds the HD sprite and its edge padding ring (4 px) is filled with the sprite colour
    for I := Low(pack.Atlases[saBase]) to High(pack.Atlases[saBase]) do
      if pack.Atlases[saBase, I].HD then
        with pack.Atlases[saBase, I] do
        begin
          CheckEquals(1, Length(Container.Sprites));
          CheckEquals(2, Container.Sprites[0].SpriteID);
          CheckEquals($FF040506, Data[Container.Sprites[0].OriginY * Container.Width + Container.Sprites[0].OriginX], 'sprite pixel');
          CheckEquals($FF040506, Data[(Container.Sprites[0].OriginY - 4) * Container.Width + Container.Sprites[0].OriginX - 4], 'padding corner');
        end;
  finally
    pack.Free;
  end;
end;


initialization
  RegisterTest('ResSprites', TestKMResSprites.Suite);
end.
