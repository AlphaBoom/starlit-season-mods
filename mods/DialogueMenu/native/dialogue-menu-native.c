// Starlit Season Steam v1.61 only. Called exclusively on UE4SS's game thread.
#include <stdint.h>
__declspec(dllimport) void* __stdcall GetModuleHandleW(const unsigned short*);
__declspec(dllimport) void* __stdcall GetProcAddress(void*,const char*);
// LuaMadeSimple::get_integer(1) reads and removes the first argument, so
// arguments are always read in order with index 1.
typedef int64_t (*GetInteger)(void*,int);
typedef void (*SetInteger)(void*,int64_t);
typedef struct {void* state;} Lua;
typedef struct {void* data;int32_t num,max;} Array;
typedef struct {void** vtable;} Malloc;
int __stdcall DllMain(void* module,unsigned reason,void* reserved){return 1;}
static uintptr_t game;
static GetInteger get;
static SetInteger put;
// Verified v1.61 entry points (first four bytes checked before use).
#define CREATE_SAVELOAD 0x125d000
#define INIT_SAVELOAD   0x125d290
#define PAUSE_COMMU     0xd57c60
#define SETUP_SLOT      0x1262470
#define SLOT_NAMES      0x4e43f30 // TArray<FString> {"slot0".."slot15"}
#define GMALLOC         0x4f08c50
#define GAME_INSTANCE   0x4ecec98 // +0x198 SaveDataManager
#define SLOT_FIND       0x10c0a50 // TMap<FString, FGameSaveDataObject>::FindId
#define SLOT_CONSTRUCT  0x10af080 // FGameSaveDataObject()
#define SLOT_ASSIGN     0x107c8f0 // FGameSaveDataObject::operator=
#define SLOT_STRIDE     0x16dd0   // map element: hash links, FString key, value at +0x10
#define SLOT_SIZE       0x16db8
#define SAVE_SLOT       0x10b2060 // SaveDataManager::Save(copyFlags, FString slotName [consumed], bool)
static int init(void){
 void* ue=GetModuleHandleW((const unsigned short*)L"UE4SS.dll");
 game=(uintptr_t)GetModuleHandleW(0);
 if(!ue||!game)return 0;
 get=(GetInteger)GetProcAddress(ue,"?get_integer@Lua@LuaMadeSimple@RC@@QEBA_JH@Z");
 put=(SetInteger)GetProcAddress(ue,"?set_integer@Lua@LuaMadeSimple@RC@@QEBAX_J@Z");
 // Fail closed on a different executable or unsupported loader.
 return get&&put&&*(uint32_t*)(game+CREATE_SAVELOAD)==0x55c48b48
  &&*(uint32_t*)(game+INIT_SAVELOAD)==0x245c8948
  &&*(uint32_t*)(game+PAUSE_COMMU)==0x245c8948
  &&*(uint32_t*)(game+SETUP_SLOT)==0x56535540
  &&*(uint32_t*)(game+SLOT_FIND)==0x245c8948
  &&*(uint32_t*)(game+SLOT_CONSTRUCT)==0x245c8948
  &&*(uint32_t*)(game+SLOT_ASSIGN)==0x245c8948
  &&*(uint32_t*)(game+SAVE_SLOT)==0x245c8948;
}
static int object(uintptr_t o){return o>0x10000&&*(uintptr_t*)o>=game&&*(uintptr_t*)o<game+0x5460000;}
static void* alloc(uint64_t size){
 Malloc* m=*(Malloc**)(game+GMALLOC);
 return m?((void*(*)(Malloc*,uint64_t,uint32_t))m->vtable[2])(m,size,0):0;
}
static void release(void* p){
 Malloc* m=*(Malloc**)(game+GMALLOC);
 if(m&&p)((void(*)(Malloc*,void*))m->vtable[4])(m,p);
}
static int same(const unsigned short* a,const char* b){
 while(*b)if(*a++!=(unsigned short)*b++)return 0;
 return *a==0;
}
__declspec(dllexport) int MenuOpen(void* state){
 Lua lua={state};
 if(!init()){if(put)put(&lua,-1);return put?1:0;}
 uintptr_t pause=(uintptr_t)get(&lua,1);
 int mode=(int)get(&lua,1);
 if(!object(pause)||(mode!=0&&mode!=1)){put(&lua,-2);return 1;}
 void* w=((void*(*)(void))(game+CREATE_SAVELOAD))();
 if(!w){put(&lua,-3);return 1;}
 // Empty TFunction callback. Lua observes removal and resumes the same parser.
 _Alignas(16) unsigned char callback[64]={0};
 ((void(*)(void*,unsigned char,unsigned char,void*,unsigned char))(game+INIT_SAVELOAD))(w,(unsigned char)mode,1,callback,0);
 ((void(*)(void*,unsigned char))(game+PAUSE_COMMU))((void*)pause,1);
 put(&lua,(int64_t)(uintptr_t)w);return 1;
}
// The save/load screen clears the dialogue input mode (CommuScriptInput +0x250)
// when it closes, which leaves both the menu and the dialogue deaf to input.
// The parser's own setters restore it: 1 = dialogue, 2 = pause menu.
#define INPUT_COMMU 0xd0e480
#define INPUT_PAUSE 0xd0e4f0
__declspec(dllexport) int MenuInput(void* state){
 Lua lua={state};if(!init())return 0;
 uintptr_t parser=(uintptr_t)get(&lua,1);int mode=(int)get(&lua,1);
 uintptr_t fn=mode==2?INPUT_PAUSE:INPUT_COMMU;
 if(object(parser)&&(mode==1||mode==2)&&*(uint32_t*)(game+fn)==0x83485340)
  ((void(*)(void*))(game+fn))((void*)parser);
 return 0;
}
// Re-asserts the dialogue's paused state (used when returning to its menu).
__declspec(dllexport) int MenuRepause(void* state){
 Lua lua={state};if(!init())return 0;
 uintptr_t pause=(uintptr_t)get(&lua,1);
 if(object(pause))((void(*)(void*,unsigned char))(game+PAUSE_COMMU))((void*)pause,1);
 return 0;
}
__declspec(dllexport) int MenuResume(void* state){
 Lua lua={state};if(!init())return 0;
 uintptr_t pause=(uintptr_t)get(&lua,1);
 if(object(pause))((void(*)(void*,unsigned char))(game+PAUSE_COMMU))((void*)pause,0);
 return 0;
}
// Appends "slotQuick" as save slot 16. The game stores slots in a TMap keyed by
// these names, so the quick slot is a separate entry next to slot0 (AUTO).
// Returns 16 on success, negative when the table is not the verified layout.
__declspec(dllexport) int SlotsExtend(void* state){
 Lua lua={state};
 if(!init()){if(put)put(&lua,-1);return put?1:0;}
 Array* names=(Array*)(game+SLOT_NAMES);
 Array* old=(Array*)names->data;
 if(names->num==17&&old&&old[16].data&&same((unsigned short*)old[16].data,"slotQuick")){put(&lua,16);return 1;}
 if(names->num!=16||!old){put(&lua,-2);return 1;}
 for(int i=0;i<16;i++){
  char text[8]={'s','l','o','t',0,0,0,0};
  if(i<10)text[4]=(char)('0'+i);else{text[4]='1';text[5]=(char)('0'+i-10);}
  if(!old[i].data||!same((unsigned short*)old[i].data,text)){put(&lua,-3);return 1;}
 }
 Array* grown=(Array*)alloc(sizeof(Array)*17);
 unsigned short* quick=(unsigned short*)alloc(sizeof(unsigned short)*10);
 if(!grown||!quick){release(grown);release(quick);put(&lua,-4);return 1;}
 for(int i=0;i<16;i++)grown[i]=old[i];
 const char* q="slotQuick";
 for(int i=0;i<10;i++)quick[i]=(unsigned short)q[i];
 grown[16].data=quick;grown[16].num=10;grown[16].max=10;
 names->data=grown;names->num=17;names->max=17;
 release(old);
 put(&lua,16);return 1;
}
// Appends a content widget to WidgetSaveLoad.SlotList (TArray at +0x3e0).
__declspec(dllexport) int SlotAppend(void* state){
 Lua lua={state};
 if(!init()){if(put)put(&lua,-1);return put?1:0;}
 uintptr_t w=(uintptr_t)get(&lua,1);uintptr_t content=(uintptr_t)get(&lua,1);
 if(!object(w)){put(&lua,-2);put(&lua,w>0x10000?(int64_t)(*(uintptr_t*)w-game):0);return 2;}
 if(!object(content)){put(&lua,-5);put(&lua,content>0x10000?(int64_t)(*(uintptr_t*)content-game):0);return 2;}
 Array* list=(Array*)(w+0x3e0);
 if(list->num<0||list->num>64){put(&lua,-3);return 1;}
 if(list->num>=list->max){
  void** grown=(void**)alloc(sizeof(void*)*(list->num+4));
  if(!grown){put(&lua,-4);return 1;}
  for(int i=0;i<list->num;i++)grown[i]=((void**)list->data)[i];
  release(list->data);list->data=grown;list->max=list->num+4;
 }
 ((void**)list->data)[list->num++]=(void*)content;
 put(&lua,list->num);return 1;
}
// Native per-slot setup: reads the slot's save data and fills the row.
__declspec(dllexport) int SlotSetup(void* state){
 Lua lua={state};if(!init())return 0;
 uintptr_t content=(uintptr_t)get(&lua,1);
 int index=(int)get(&lua,1);int flag=(int)get(&lua,1);
 Array* names=(Array*)(game+SLOT_NAMES);
 if(object(content)&&index>=0&&index<names->num)
  ((void(*)(void*,int,unsigned char,unsigned char))(game+SETUP_SLOT))((void*)content,index,0,(unsigned char)flag);
 return 0;
}

// Saving inside a dialogue. A manual save first clears the working save object
// and stores only the live user data, which resumes at the start of the phase
// (PRODUCE TIME even when the dialogue was reached in FREE TIME). The AUTO save
// (slot0) written when the dialogue starts holds the full resume point. After the
// game saved slot N from a dialogue, store a copy of AUTO under slot N instead:
// put AUTO in the working object and run the game's own save with no copy flags,
// which stores the working object under the slot name and writes the file.
typedef void (*Assign)(void*,const void*);
static unsigned char* snapshot;
static int64_t before[32];
static int beforeCount;
static uintptr_t saveManager(void){
 uintptr_t instance=*(uintptr_t*)(game+GAME_INSTANCE);
 if(!object(instance))return 0;
 uintptr_t m=*(uintptr_t*)(instance+0x198);
 return object(m)?m:0;
}
static unsigned char* slotValue(uintptr_t m,int index){
 uintptr_t master=*(uintptr_t*)(m+0x39e0);
 Array* names=(Array*)(game+SLOT_NAMES);
 if(!object(master)||index<0||index>=names->num)return 0;
 int id=-1;
 int* found=((int*(*)(void*,int*,void*))(game+SLOT_FIND))((void*)(master+0x30),&id,&((Array*)names->data)[index]);
 if(!found||*found<0)return 0;
 return (unsigned char*)(*(uintptr_t*)(master+0x30)+(uintptr_t)*found*SLOT_STRIDE+0x10);
}
// Save timestamp (UserSaveData.SaveTime); play time does not move while paused.
static int64_t slotTime(uintptr_t m,int index){
 unsigned char* v=slotValue(m,index);
 return v?*(int64_t*)(v+0x38+8):-1;
}
static int64_t playTime(unsigned char* v){return *(int64_t*)(v+0x30);}
// Remembers every slot's play time when the save screen opens.
__declspec(dllexport) int DialogueSaveBegin(void* state){
 Lua lua={state};
 if(!init()){if(put)put(&lua,-1);return put?1:0;}
 uintptr_t m=saveManager();
 if(!m){put(&lua,-2);return 1;}
 Array* names=(Array*)(game+SLOT_NAMES);
 beforeCount=names->num<32?names->num:32;
 for(int i=0;i<beforeCount;i++)before[i]=slotTime(m,i);
 put(&lua,1);return 1;
}
// Called when the save screen is idle again. Arguments: save/load widget.
// Returns the slot index rewritten from AUTO, 0 when nothing changed, or negative.
__declspec(dllexport) int DialogueSaveFix(void* state){
 Lua lua={state};
 if(!init()){if(put)put(&lua,-1);return put?1:0;}
 uintptr_t w=(uintptr_t)get(&lua,1);
 uintptr_t m=saveManager();
 if(!m||!object(w)){put(&lua,-2);return 1;}
 int index=*(int*)(w+0x4e0);
 if(index<=0||index>=beforeCount){put(&lua,0);return 1;}
 int64_t now=slotTime(m,index);
 if(now==before[index]){put(&lua,0);return 1;} // cancelled or not saved
 unsigned char* autosave=slotValue(m,0);
 if(!autosave){put(&lua,-3);return 1;}
 // AUTO from a later point than this save (another playthrough): keep the game's save.
 unsigned char* saved=slotValue(m,index);
 if(!saved||playTime(autosave)>playTime(saved)){before[index]=now;put(&lua,-4);return 1;}
 Array* names=(Array*)(game+SLOT_NAMES);
 Array* name=&((Array*)names->data)[index];
 unsigned short* copy=(unsigned short*)alloc((uint64_t)name->num*2);
 if(!copy){put(&lua,-5);return 1;}
 for(int i=0;i<name->num;i++)copy[i]=((unsigned short*)name->data)[i];
 Array arg={copy,name->num,name->num};
 if(!snapshot){
  snapshot=(unsigned char*)alloc(SLOT_SIZE+0x40);
  if(!snapshot){release(copy);put(&lua,-6);return 1;}
  ((void(*)(void*))(game+SLOT_CONSTRUCT))(snapshot);
 }
 unsigned char* working=(unsigned char*)(m+0x39e8);
 ((Assign)(game+SLOT_ASSIGN))(snapshot,working);
 ((Assign)(game+SLOT_ASSIGN))(working,autosave);
 ((void(*)(void*,unsigned char,void*,unsigned char))(game+SAVE_SLOT))((void*)m,0,&arg,*(unsigned char*)(w+0x502));
 ((Assign)(game+SLOT_ASSIGN))(working,snapshot);
 before[index]=slotTime(m,index);
 put(&lua,index);return 1;
}
