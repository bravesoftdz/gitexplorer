unit FormMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, ShellCtrls,
  ComCtrls, process, gqueue, syncobjs;

type
  TNodeQueue = specialize TQueue<TShellTreeNode>;

  { TUpdateThread }

  TUpdateThread = class(TThread)
    procedure Execute; override;
  end;

  { TFMain }

  TFMain = class(TForm)
    ShellTreeView1: TShellTreeView;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure ShellTreeView1Expanded(Sender: TObject; Node: TTreeNode);
    procedure ShellTreeView1MouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  private
    FQueueLock: TCriticalSection;
    FUpdateQueue: TNodeQueue;
    FUpdateThread: TUpdateThread;
    FGitExe: String;
    procedure QueryStatus(N: TShellTreeNode; QueueUpdate: Boolean);
    procedure AsyncQueryStatus(P: PtrInt);
    procedure UpdateAllNodes(Root: TTreeNode);
    { private declarations }
  public
    { public declarations }
  end;

var
  FMain: TFMain;

implementation
{$ifdef windows}
uses
  Windows;
{$endif}

procedure Print(Txt: String);
begin
  {$ifdef windows}
  OutputDebugString(PChar(Txt));
  {$else}
  Writeln(Txt);
  {$endif}
end;

function RunTool(Path: String; cmd: String; args: array of string; out ConsoleOutput: String): Boolean;
var
  P: TProcess;
  A: String;
begin
  P := TProcess.Create(nil);
  P.CurrentDirectory := Path;
  P.Options := [poUsePipes, poNoConsole];
  P.Executable := cmd;
  for A in args do
    P.Parameters.Add(A);
  P.Execute;
  repeat
    Sleep(1);
    while P.Output.NumBytesAvailable > 0 do
      ConsoleOutput += Chr(P.Output.ReadByte);
    if ThreadID = MainThreadID then
      Application.ProcessMessages;
  until not (P.Running or (P.Output.NumBytesAvailable > 0));
  Result := (P.ExitCode = 0);
  P.Free;
end;

{$R *.lfm}

{ TUpdateThread }

procedure TUpdateThread.Execute;
var
  Node: TShellTreeNode;
  O: String;
begin
  repeat
    if FMain.FUpdateQueue.Size() > 0 then begin
      FMain.FQueueLock.Acquire;
      Node := FMain.FUpdateQueue.Front();
      FMain.FUpdateQueue.Pop();
      FMain.FQueueLock.Release;
      if RunTool(Node.FullFilename, Fmain.FGitExe, ['remote', 'update'], O) then begin
        Application.QueueAsyncCall(@FMain.AsyncQueryStatus, PtrInt(Node));
      end;
    end
    else
      Sleep(1);
  until Terminated;
end;

{ TFMain }

procedure TFMain.ShellTreeView1MouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);

var
  N: TTreeNode;

begin
  if Button = mbRight then begin
    N := ShellTreeView1.GetNodeAt(X, Y);
    if Assigned(N) then
       N.Selected := True;
  end;
end;

procedure TFMain.QueryStatus(N: TShellTreeNode; QueueUpdate: Boolean);
var
  Path: String;
  O: String;
  Behind: Boolean = False;
  Ahead: Boolean = False;
  Clean: Boolean = False;
begin
  Path := N.FullFilename;
  if DirectoryExists(Path + DirectorySeparator + '.git') then begin
    if RunTool(Path, FGitExe, ['status'], O) then begin
      N.Text := N.ShortFilename;
      if Pos('behind', O) > 0 then
        Behind := True;
      if Pos('ahead', O) > 0 then
        Behind := True;
      if Pos('clean', O) > 0 then
        Clean := True;
      if Behind then
        N.Text := '[BEHIND] ' + N.Text;
      if Ahead then
        N.Text := '[AHEAD] ' + N.Text;
      if not Clean then
        N.Text := '[DIRTY] ' + N.Text;
    end;
    N.Text := '# ' + N.Text;
    if QueueUpdate then begin
      FQueueLock.Acquire;
      FUpdateQueue.Push(N);
      FQueueLock.Release;
    end;
  end;
end;

procedure TFMain.AsyncQueryStatus(P: PtrInt);
begin
  QueryStatus(TShellTreeNode(P), False);
end;

procedure TFMain.UpdateAllNodes(Root: TTreeNode);
var
  N: TShellTreeNode;
begin
  N := TShellTreeNode(Root.GetFirstChild);
  while Assigned(N) do begin
    QueryStatus(N, True);
    N := TShellTreeNode(N.GetNextSibling);
  end;
end;

procedure TFMain.FormShow(Sender: TObject);
begin
  UpdateAllNodes(ShellTreeView1.TopItem);
end;

procedure TFMain.FormCreate(Sender: TObject);
begin
  FQueueLock := syncobjs.TCriticalSection.Create;
  FUpdateQueue := TNodeQueue.Create;
  FGitExe := 'c:\Program Files (x86)\Git\bin\git.exe';
  ShellTreeView1.Root := GetUserDir;
  FUpdateThread := TUpdateThread.Create(False);
end;

procedure TFMain.FormDestroy(Sender: TObject);
begin
  FUpdateQueue.Free;
  FQueueLock.Free;
end;

procedure TFMain.ShellTreeView1Expanded(Sender: TObject; Node: TTreeNode);
begin
  UpdateAllNodes(Node);
end;

end.

