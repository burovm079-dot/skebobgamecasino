/* SKEBOB GAME — Supabase nickname/password accounts */
(function(){
"use strict";
const SB_URL="https://pvlkcgdayxvxzvbnbuih.supabase.co";
const SB_KEY="sb_publishable_abz-qQOtxrQ8pLJh5lo0LQ_ylXsjiFh";
const SESSION_KEY="skebobSupabaseSession";
let session=null, authMode="login", currentNickname="";

function emailForNickname(nickname){
 const bytes=new TextEncoder().encode(String(nickname).trim().toLocaleLowerCase("ru"));
 let binary=""; bytes.forEach(b=>binary+=String.fromCharCode(b));
 const encoded=btoa(binary).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
 return "u"+encoded+"@players.skebobgame.com";
}
function cleanNickname(value){return String(value||"").trim().replace(/\s+/g," ").slice(0,18);}
function showMessage(message,isError){
 const el=document.getElementById("authMessage");
 if(el){el.textContent=message||"";el.style.color=isError?"#ff8585":"#b7e6b7";}
}
async function parseResponse(response){
 let data={}; try{data=await response.json();}catch(_){}
 if(!response.ok){
  const msg=data.msg||data.message||data.error_description||data.error||"Ошибка соединения с сервером";
  throw new Error(String(msg));
 }
 return data;
}
async function authRequest(path,body){
 const response=await fetch(SB_URL+"/auth/v1/"+path,{method:"POST",headers:{"Content-Type":"application/json","apikey":SB_KEY},body:JSON.stringify(body)});
 return parseResponse(response);
}
async function authUpdateUser(body){
 const response=await fetch(SB_URL+"/auth/v1/user",{method:"PUT",headers:{"Content-Type":"application/json","apikey":SB_KEY,"Authorization":"Bearer "+session.access_token},body:JSON.stringify(body)});
 return parseResponse(response);
}
async function changeAccountNickname(value){
 const nick=cleanNickname(value);
 const problem=nicknameError(nick);
 if(problem)throw new Error(problem);
 if(!session||!session.user||!session.user.id)throw new Error("Сначала войди в аккаунт.");
 if(nick.toLocaleLowerCase("ru")===String(currentNickname).toLocaleLowerCase("ru"))return true;
 const rows=await rest("player_profiles?user_id=eq."+encodeURIComponent(session.user.id),{
  method:"PATCH",
  headers:{"Prefer":"return=representation"},
  body:JSON.stringify({nickname:nick})
 });
 if(!Array.isArray(rows)||!rows.length)throw new Error("Профиль не обновился. Возможно, этот ник уже занят.");
 try{await authUpdateUser({data:{...(session.user.user_metadata||{}),nickname:nick}});}catch(error){console.warn("Nickname metadata update:",error);}
 currentNickname=nick;
 if(session.user){session.user.user_metadata={...(session.user.user_metadata||{}),nickname:nick};}
 saveSession(session);
 try{localStorage.setItem("skebobNickname",nick);}catch(_){}
 if(typeof updateNicknameUI==="function")updateNicknameUI();
 if(typeof render==="function")render();
 if(typeof save==="function")save();
 if(window.skebobQueueSave)window.skebobQueueSave();
 return true;
}
function saveSession(value){
 session=value;
 if(value&&value.access_token&&value.refresh_token){
  try{localStorage.setItem(SESSION_KEY,JSON.stringify(value));}catch(_){}
 }else{
  try{localStorage.removeItem(SESSION_KEY);}catch(_){}
 }
}
async function rest(path,options={}){
 if(!session||!session.access_token)throw new Error("Сессия не найдена. Войди в аккаунт ещё раз.");
 const response=await fetch(SB_URL+"/rest/v1/"+path,{...options,headers:{"apikey":SB_KEY,"Authorization":"Bearer "+session.access_token,"Content-Type":"application/json","Accept":"application/json",...(options.headers||{})}});
 return parseResponse(response);
}
async function refreshSession(){
 let old=null;try{old=JSON.parse(localStorage.getItem(SESSION_KEY)||"null");}catch(_){}
 if(!old||!old.refresh_token)return false;
 try{
  const fresh=await authRequest("token?grant_type=refresh_token",{refresh_token:old.refresh_token});
  saveSession(fresh);return true;
 }catch(_){saveSession(null);return false;}
}
function showAuth(){
 const modal=document.getElementById("skebobAuthModal");
 if(modal)modal.style.display="flex";
 const n=document.getElementById("authNickname");
 if(n)setTimeout(()=>n.focus(),200);
}
function setMode(mode){
 authMode=mode==="register"?"register":"login";
 const title=document.getElementById("authTitle"),desc=document.getElementById("authDescription"),submit=document.getElementById("authSubmit"),repeat=document.getElementById("authRepeatWrap"),toggle=document.getElementById("authModeToggle");
 if(title)title.textContent=authMode==="register"?"СОЗДАТЬ АККАУНТ":"С ВОЗВРАЩЕНИЕМ!";
 if(desc)desc.textContent=authMode==="register"?"Придумай ник и пароль. Аккаунт сохранит твой игровой прогресс.":"Введи свой ник и пароль, чтобы продолжить игру.";
 if(submit)submit.textContent=authMode==="register"?"ЗАРЕГИСТРИРОВАТЬСЯ":"ВОЙТИ В ИГРУ";
 if(repeat)repeat.style.display=authMode==="register"?"block":"none";
 if(toggle)toggle.textContent=authMode==="register"?"Уже есть аккаунт? Войти":"Нет аккаунта? Зарегистрироваться";
 showMessage("");
}
function nicknameError(nick){
 if(nick.length<2||nick.length>18)return "Ник должен содержать от 2 до 18 символов.";
 if(!/[\p{L}\p{N}]/u.test(nick))return "В нике должна быть хотя бы одна буква или цифра.";
 if(typeof bjIsOfficialNickname==="function"&&bjIsOfficialNickname(nick))return "Этот ник зарезервирован.";
 if(typeof bjIsSpecialAccount==="function"&&bjIsSpecialAccount(nick))return "Этот ник зарезервирован.";
 return "";
}
function normalizeLoadedState(remote){
 if(!remote||typeof remote!=="object"||Array.isArray(remote))return;
 delete remote.admin;
 state={...state,...remote,
  stats:{...(typeof defaultStats!=="undefined"?defaultStats:{}),...(remote.stats||{})},
 };
 if(!state.inventory||!Array.isArray(state.inventory))state.inventory=[];
 if(!state.tapGame||typeof state.tapGame!=="object")state.tapGame={hourStartedAt:0,earnedCents:0,pendingCents:0,cooldownUntil:0};
}
async function loadPlayerData(){
 const uid=session.user.id;
 let profileRows=await rest("player_profiles?select=nickname&user_id=eq."+encodeURIComponent(uid)+"&limit=1");
 if(!Array.isArray(profileRows)||!profileRows.length)throw new Error("Профиль не найден. Проверь SQL-триггер в Supabase.");
 currentNickname=profileRows[0].nickname;
 let rows=await rest("player_saves?select=game_state&user_id=eq."+encodeURIComponent(uid)+"&limit=1");
 const remote=rows&&rows[0]&&rows[0].game_state;
 if(remote&&typeof remote==="object"&&!Array.isArray(remote)&&Object.keys(remote).length){
  normalizeLoadedState(remote);
 }else{
  // При первой регистрации переносим локальное сохранение этого устройства в аккаунт.
  if(typeof hasExistingSave!=="undefined"&&hasExistingSave){
   await writePlayerSave();
  }else{
   await writePlayerSave();
  }
 }
 try{localStorage.setItem("skebobNickname",currentNickname);}catch(_){}
 if(typeof render==="function")render();
 if(typeof updateUpgradeInfo==="function")updateUpgradeInfo();
 if(typeof updateNicknameUI==="function")updateNicknameUI();
 const modal=document.getElementById("skebobAuthModal");if(modal)modal.style.display="none";
}
async function writePlayerSave(){
 if(!session||!session.user||!session.user.id)return;
 const response=await fetch(SB_URL+"/rest/v1/player_saves?on_conflict=user_id",{method:"POST",headers:{"apikey":SB_KEY,"Authorization":"Bearer "+session.access_token,"Content-Type":"application/json","Prefer":"resolution=merge-duplicates,return=minimal"},body:JSON.stringify({user_id:session.user.id,game_state:state})});
 if(response.status===401&&await refreshSession())return writePlayerSave();
 if(!response.ok){let msg="Не удалось сохранить прогресс";try{const d=await response.json();msg=d.message||d.details||msg;}catch(_){}throw new Error(msg);}
}
let saveTimer=null;
window.skebobQueueSave=function(){
 if(!session||!session.user)return;
 clearTimeout(saveTimer);
 saveTimer=setTimeout(()=>writePlayerSave().catch(e=>{console.warn("Supabase save:",e);showMessage("Не удалось синхронизировать прогресс. Проверь интернет.");}),1200);
};
async function submitAuth(){
 const button=document.getElementById("authSubmit");
 if(button&&button.disabled)return;
 const nick=cleanNickname(document.getElementById("authNickname")?.value);
 const password=String(document.getElementById("authPassword")?.value||"");
 const repeat=String(document.getElementById("authPasswordRepeat")?.value||"");
 const problem=nicknameError(nick);
 if(problem){showMessage(problem,true);return;}
 if(password.length<6){showMessage("Пароль должен содержать минимум 6 символов.",true);return;}
 if(authMode==="register"&&password!==repeat){showMessage("Пароли не совпадают.",true);return;}
 if(button){button.disabled=true;button.textContent="ПОДОЖДИ…";}
 showMessage(authMode==="register"?"Создаём аккаунт…":"Выполняем вход…");
 try{
  let email=emailForNickname(nick);
  if(authMode==="login"){
   const lookupResponse=await fetch(SB_URL+"/rest/v1/rpc/get_player_login_email",{method:"POST",headers:{"apikey":SB_KEY,"Content-Type":"application/json"},body:JSON.stringify({p_nickname:nick})});
   const lookupData=await parseResponse(lookupResponse);
   email=typeof lookupData==="string"?lookupData:"";
   if(!email)throw new Error("Игрок с таким ником не найден.");
  }
  if(authMode==="register"){
   const result=await authRequest("signup",{email,password,data:{nickname:nick}});
   if(!result.session){
    showMessage("Регистрация почти готова. В Supabase отключи подтверждение Email: Authentication → Providers → Email → Confirm email OFF. Затем попробуй зарегистрироваться снова.",true);
    return;
   }
   saveSession(result.session);
  }else{
   const result=await authRequest("token?grant_type=password",{email,password});
   saveSession(result);
  }
  await loadPlayerData();
 }catch(error){
  let message=error.message||"Неизвестная ошибка";
  if(/already registered|user already registered/i.test(message))message="Этот ник уже занят. Если это твой аккаунт — войди.";
  if(/invalid login credentials/i.test(message))message="Неверный ник или пароль.";
  if(/nickname|duplicate key|unique constraint/i.test(message))message="Этот ник уже занят. Придумай другой.";
  showMessage(message,true);
  if(session&&session.access_token){saveSession(null);}
 }finally{
  if(button){button.disabled=false;button.textContent=authMode==="register"?"ЗАРЕГИСТРИРОВАТЬСЯ":"ВОЙТИ В ИГРУ";}
 }
}
window.initSupabaseAuth=async function(){
 setMode("login");
 const form=document.getElementById("skebobAuthForm");
 if(form)form.addEventListener("submit",e=>{e.preventDefault();submitAuth();});
 const toggle=document.getElementById("authModeToggle");
 if(toggle)toggle.addEventListener("click",()=>setMode(authMode==="login"?"register":"login"));
 try{
  const stored=JSON.parse(localStorage.getItem(SESSION_KEY)||"null");
  if(stored&&stored.access_token&&stored.refresh_token){
   session=stored;
   if(Date.now()/1000>(Number(stored.expires_at)||0)-60)await refreshSession();
   if(session&&session.access_token){try{await loadPlayerData();return;}catch(e){console.warn("Session restore:",e);saveSession(null);}}
  }
 }catch(e){console.warn("Auth restore:",e);}
 showAuth();
};
window.getNickname=function(){return currentNickname||"Player";};
window.persistNickname=function(){return false;};
window.skebobChangeNickname=changeAccountNickname;
window.skebobChangePassword=async function(currentPassword,newPassword){
 if(!session||!session.user||!session.user.email)throw new Error("Сессия не найдена. Войди в аккаунт ещё раз.");
 if(typeof currentPassword!=="string"||currentPassword.length<6)throw new Error("Введи текущий пароль.");
 if(typeof newPassword!=="string"||newPassword.length<6)throw new Error("Новый пароль должен содержать минимум 6 символов.");
 // Verify the current password with Supabase Auth before allowing a password update.
 await authRequest("token?grant_type=password",{email:session.user.email,password:currentPassword});
 await authUpdateUser({password:newPassword});
 return true;
};
window.skebobLogout=async function(){
 try{if(session&&session.access_token)await fetch(SB_URL+"/auth/v1/logout",{method:"POST",headers:{"apikey":SB_KEY,"Authorization":"Bearer "+session.access_token}});}catch(_){}
 saveSession(null);currentNickname="";showAuth();
};
})();
