const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('shiro',{
  call:(action,payload)=>ipcRenderer.invoke('shiro',action,payload),
  onUpdate:callback=>{const handler=(_,value)=>callback(value);ipcRenderer.on('update',handler);return()=>ipcRenderer.removeListener('update',handler);}
});
