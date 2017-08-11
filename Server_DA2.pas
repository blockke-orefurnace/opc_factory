unit Server_DA2;

//------------------------------------------------------------------------------
                                interface
//------------------------------------------------------------------------------

uses
  SysUtils, Classes, prOpcServer, prOpcTypes, Hashes, Server_UDP;

type
  FagotDA = class(TOpcItemServer)
  private
    hashItemID: TIntegerHash;

  protected
    function Options: TServerOptions; override;
    procedure OnClientConnect(Client: TClientInfo); override;
    procedure OnClientDisconnect(Client: TClientInfo); override;

    procedure OnClientSetName(Client: TClientInfo); override;
    procedure OnAddGroup(Group: TGroupInfo); override;
    procedure OnRemoveGroup(Group: TGroupInfo); override;
    procedure OnAddItem(Item: TGroupItemInfo); override;
    procedure OnRemoveItem(Item: TGroupItemInfo); override;
  public
    function GetItemInfo(const ItemID: String; var AccessPath: string;
                         var AccessRights: TAccessRights): Integer; override;

    procedure ReleaseHandle(ItemHandle: TItemHandle); override;
    procedure ListItemIds(List: TItemIDList); override;

    function GetItemValue(ItemHandle: TItemHandle;
                          var Quality: Word): OleVariant; override;

    procedure SetItemValue(ItemHandle: TItemHandle; const Value: OleVariant); override;

    constructor Create;
    destructor Destroy;
  end;

const
  ServerGuid: TGUID = '{CAE8D0E1-117B-11D5-944B-00C0F023FA1C}';
  ServerVersion = 1;
  ServerDesc = 'Fagot OPC DA - prOpcKit';
  ServerVendor = 'Production Robots Eng. Ltd';

  {
    ������ ������� � UDP --> TItems = array[0..2100] of TServItem;
    �� 1 �� 2000 - ������
    �� 2001 �� 2100 - ��������� ���� - ����������, ������
  }
  countItem = 2000;

var
  // TODO: ��������� ������������� ���������� ���������� ��� ���������� �������
  countClient: Integer = 0; // ���������� �������� ��������

//------------------------------------------------------------------------------
                              implementation
//------------------------------------------------------------------------------

uses
  Server_Devices, prOpcError, Windows;

constructor FagotDA.Create;
begin
  inherited Create;
  hashItemID := TIntegerHash.Create;
  countClient := 0;
end;

destructor FagotDA.Destroy;
begin
  FreeAndNil(hashItemID);
  inherited Destroy;
end;

{
  ������� OPC �� ������ ������������ �������� � ������������ �� �������������, 
  �� ����������� ��� ������, � ������ ������� �������� ���������� ������������� � �� ��������������� ��������. 
  ������������ OPC ���������� ��� ���� ���������: ������� � �������������. ���������� prOpc ������������ ��� �������, 
  ��� � ������������� ��������. � ���� ������� �� ��������� ������� ������������ ����. 

 ��� ��������� ��������� ��� ���������� ����������� ������� ListItemIds. 
 ��� ���� ������� ��������� ����������, ��������������� GetItemInfo, 
 �� ��� ������������ �������������� ����������� ��� ������ �� ���������.
 
  �������� ��������, ��� �������� �VarType� ������ ���� ����������� � COM-�����. 
  ���������� � ������������ Delphi �� ����� ������� - � ���������� ������� OleVariant ���� ������� �������. 
  �� ������ ������ ����� ����� �������������� ��������� ����� �����:

    - varInteger
    - varDouble
    - varCurrency
    - varDate
    - varOleStr
    - varBoolean

  ��������������: ������� �� ����������� varString - ��� �������� ������ ANSI, ������� �� �������� ����������� � COM-�����.
  ������� GetItemValue �� ����� ���������� ���� ��� � ����� ������, ��������� ���������� OleVariant,
  ������� �� ����� ��������� ��������� �������� ANSI.

  �� ����� ������ ������������ ���������� ��� varSmallint � varByte, �� � �� ���� ��������� ������ ��������� ��� �����.
  ����� �� �������� ����������� �������������� �������� ��������� VarType �������� ����� ������ ������������ �GetItemValue�,
  � ����� ������������� ������� VarType ��� ���������� ���� ��� ����.
}

procedure FagotDA.ListItemIDs(List: TItemIDList);
var
  i : Integer;
  VarType: Integer;
begin
  log.Info('Browsing OPC tag');

  for i := 1 to countItem - 1 do
  begin
    if Assigned(serv.Items[i]) then
    begin

      // ������ ������������� ��� ������
      case serv.Items[i].SIType of
        1: VarType := varBoolean;
        2: VarType := varByte;
        3: VarType := varWord;
        4: VarType := varInteger;
        5: VarType := varDouble;
      else
        VarType := varInteger;
      end;

      if serv.Items[i].iswrite then
        List.AddItemId( serv.Items[i].name, [iaRead, iaWrite], VarType)
      else
        List.AddItemId( serv.Items[i].name, [iaRead], VarType);

      hashItemID.Items[AnsiLowerCase(serv.Items[i].name)] := i;
    end;
  end;
end;

{
  ����� ������ �������� ������������ � �������, �������������� ������� GetItemInfo 
  ��� ��������� ����������� ��� ���������� �� ��������.
  
  ����� ����� ������������ �������� GetItemInfo, �� ���������� �������� GetItemValue 
  ��� ��������� �������� �sample� � �������� OleVariant. ����� �� ���������� ��� ����� 
  ������������� �������� ��� ����������� ��� ��������. �� ���� ������� �� ������ ���� �������, 
  ��� GetItemValue ����� ������� ��������, ��� ������ GetItemInfo ��������, 
  ���� ���� ��� �������� �������� ���������� ���������.
}
function FagotDA.GetItemInfo(const ItemID: String; var AccessPath: string;
       var AccessRights: TAccessRights): Integer;
var
  i : Integer;
begin

  Result:= 0;

  // ��������� ���������� ���-������.
  // ���-������ ����� ������ ���� ��������� ��� ��� ���������������� ��������� ����� OPCItemServer.InitBrowsing
  if hashItemID.ItemCount = 0 then
  begin
    hashItemID.Clear;

    for i := 1 to countItem - 1 do
    begin
      if Assigned(serv.Items[i]) then
      begin

        if serv.Items[i].iswrite then
          AccessRights := [iaRead, iaWrite]
        else
          AccessRights := [iaRead];

        hashItemID.Items[AnsiLowerCase(serv.Items[i].name)] := i;
      end;
    end;
  end;

  try
    Result:= hashItemID.Items[AnsiLowerCase(ItemID)];
    log.debug('Server_DA2-->GetItemInfo: ' + IntToStr(Result) + ' - ' + ItemID );

  except
    log.error('Module Server_DA2-->GetItemInfo: OPC_E_INVALIDITEMID - ' + ItemID);
    raise EOpcError.Create(OPC_E_INVALIDITEMID);
  end;
end;

 {
    ��������, ��� ����������� �������� ������ ��� ������ ������, ����� ����������� ���� ���������� ��������. 
    ���� �� ��� ��������, ��� ����� ����� �����, ����� ����� ���������� ��� �������. 
    ReleaseHandle ����������, ����� ����� ������������ �������� � ������� ������ �����������. 
    ��� ����������, ����� ��� ������� �����������, ��� ��� ������, ������������ ��� �������, ���� �������.
  }
procedure FagotDA.ReleaseHandle(ItemHandle: TItemHandle);
begin
  {Release the handle previously returned by GetItemInfo}
end;

{
  C������ ��������, ��� ���� ��������, ������������ GetItemValue, �������� OleVariant, 
  ��� ������������� �������� (����� �����, ������ � �. �.) �� ������ �������� � ������� ����� 
  ����� ������ ���������� , ��� ������ GetItemInfo ��������, �� ������ ���������, ��� GetItemValue 
  �������� ���������� �������� ����������� ����. ����������� �������� �� ����� ��������, �� ��� �����. 
  ���� �� ������ �������, ��� ������������ �������� ������� ��� �������, �� ������ ������������
  �������� ���������, ����� ������� ����, ������ OPC_QUALITY_OUT_OF_SERVICE, �� �� ������ ������ 
  ���������� �������� ����������� ����. ���������� delphi �� ����� ����������, ���� �� ����� �� ��������,
  ��� ��� ������� �������� OleVariant ������������� ���������������� �� �����������������. 
  �� ����������� �� ����������, ����� ������� ���.
  
  �������� ��������
  � ����� ����� ������ �������� ��������� �������� �������� ����������, ������� ����� 
  �������������� ��� �������� ����, ��� ������������ �������� ������ 100% ������� ��� �����������. 
  ��� ���������� ���������� �������� �������� ��� ����� ����� ���������� � ������������ ������� � ������ OPC. 
  ����������� �������� �������� ����������� � ����� prOpcDa ��������� �������:
  
// Masks for extracting quality subfields
// (note 'status' mask also includes 'Quality' bits)
  
  OPC_QUALITY_MASK           = $C0;
  OPC_STATUS_MASK            = $FC;
  OPC_LIMIT_MASK             = $03;

// Values for QUALITY_MASK bit field
  OPC_QUALITY_BAD            = $00; �����
  OPC_QUALITY_UNCERTAIN      = $40; �����������
  OPC_QUALITY_GOOD           = $C0; ������

// STATUS_MASK Values for Quality = BAD
  OPC_QUALITY_CONFIG_ERROR   = $04; ������ ������������
  OPC_QUALITY_NOT_CONNECTED  = $08; �� ���������
  OPC_QUALITY_DEVICE_FAILURE = $0C; ����� ����������
  OPC_QUALITY_SENSOR_FAILURE = $10; ���� �������
  OPC_QUALITY_LAST_KNOWN     = $14; ��������� ���������
  OPC_QUALITY_COMM_FAILURE   = $18; ���� �����
  OPC_QUALITY_OUT_OF_SERVICE = $1C; �� ��������

// STATUS_MASK Values for Quality = UNCERTAIN
  OPC_QUALITY_LAST_USABLE    = $44; // ��������� ��������
  OPC_QUALITY_SENSOR_CAL     = $50; // ����� �������
  OPC_QUALITY_EGU_EXCEEDED   = $54; // ��������� egu
  OPC_QUALITY_SUB_NORMAL     = $58; // ��� ����������

// STATUS_MASK Values for Quality = GOOD
  OPC_QUALITY_LOCAL_OVERRIDE = $D8; // ��������� ���������������


����� ���������� GetItemValue, �������� ��������� ���������������� OPC_QUALITY_GOOD. 
� ����������� ������� ��� ��������, ������� �� ������ �������, 
������� �� ������ ������������ ���� ��������.  
}
function FagotDA.GetItemValue(ItemHandle: TItemHandle;
                           var Quality: Word): OleVariant;
begin
  {return the value of the item identified by ItemHandle}
  if Assigned(serv.Items[ItemHandle]) then
    begin
      //Quality := serv.Items[ItemHandle].quality;
      Result:= serv.Items[ItemHandle].value;
    end
  else
    begin
      Result:= 0;
      raise EOpcError.Create(OPC_E_INVALIDHANDLE);
      log.error('Module Server_DA2-->GetItemValue: OPC_E_INVALIDHANDLE - '+ IntToStr(ItemHandle));
    end;

end;

procedure FagotDA.SetItemValue(ItemHandle: TItemHandle; const Value: OleVariant);
begin
  {set the value of the item identified by ItemHandle}

  if Assigned(serv.Items[ItemHandle]) then    // �������� ������������� ����
    begin
      if serv.Items[ItemHandle].iswrite then   // �������� ����������� �� ������
      begin
        serv.SetItemValue(ItemHandle, Value);
      end
      else
      begin
        raise EOpcError.Create(OPC_E_NOTSUPPORTED);
        log.error('Module Server_DA2-->SetItemValue: OPC_E_NOTSUPPORTED - '+ IntToStr(ItemHandle));
      end;
    end
  else
  begin
    raise EOpcError.Create(OPC_E_INVALIDHANDLE);
    log.error('Module Server_DA2-->SetItemValue: OPC_E_INVALIDHANDLE - '+ IntToStr(ItemHandle));
  end;

end;

function FagotDA.Options: TServerOptions;
begin
  Result:= [soHierarchicalBrowsing, soAlwaysAllocateErrorArrays]
 //Result:= [soHierarchicalBrowsing]
end;


procedure FagotDA.OnClientConnect(Client: TClientInfo);
begin
  {Code here will execute whenever a client connects}
  try
   countClient := ClientCount;
  finally
   log.Info('OPC Client Connect: ' + Client.ClientName + '. Count clients: ' + IntToStr(countClient) );
  end;
end;

procedure FagotDA.OnClientDisconnect(Client: TClientInfo);
begin
  {Code here will execute whenever a client connects}
  try
    countClient := ClientCount;
  finally
   log.Info('OPC Client Disconnect: ' + Client.ClientName + '. Count clients: ' + IntToStr(countClient));
  end;
end;

procedure FagotDA.OnClientSetName(Client: TClientInfo);
begin
  {Code here will execute whenever a client calls IOpcCommon.SetClientName}
  log.Info( Format('Client SetName %s',[Client.ClientName]) );
end;

procedure FagotDA.OnAddGroup(Group: TGroupInfo);
begin
  {Code here will execute whenever a client adds a group}
  log.Info( Format('Add Group %s ok', [Group.Name]) );
end;

procedure FagotDA.OnRemoveGroup(Group: TGroupInfo);
begin
  {Code here will execute whenever a client removes a group}
  log.Info( Format('Remove Group %s ok', [Group.Name]) );
end;

procedure FagotDA.OnAddItem(Item: TGroupItemInfo);
begin
  {Code here will execute whenever a client adds an item to a group}
  log.Info( Format('Add Item %s ok', [Item.ItemID]) );
end;

procedure FagotDA.OnRemoveItem(Item: TGroupItemInfo);
begin
  {Code here will execute whenever a client removes an item from a group}
  log.Info( Format('Remove Item %s ok', [Item.ItemID]) );
end;

initialization
  RegisterOPCServer(ServerGUID, ServerVersion, ServerDesc, ServerVendor, FagotDA.Create)
 

end.

