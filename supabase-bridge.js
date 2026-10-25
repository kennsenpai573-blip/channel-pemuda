/* Supabase connection + safe frontend helpers. Database policies live in supabase/schema.sql. */
(function(){
  const STORE_KEY = 'pc_supabase_config_v1';
  function readConfig(){
    let saved={}; try{saved=JSON.parse(localStorage.getItem(STORE_KEY)||'{}')}catch{}
    const base=window.PEMUDAQ_SUPABASE_CONFIG||{};
    return {url:(saved.url||base.url||'').trim(), anonKey:(saved.anonKey||base.anonKey||'').trim()};
  }
  let client=null;
  function init(){
    const cfg=readConfig();
    if(!cfg.url||!cfg.anonKey||!window.supabase?.createClient){client=null;window.pcSupabase=null;return null;}
    try{client=window.supabase.createClient(cfg.url,cfg.anonKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});window.pcSupabase=client;return client;}
    catch(e){console.error('Supabase init failed',e);client=null;window.pcSupabase=null;return null;}
  }
  window.PemudaSupabase={
    getConfig:readConfig,
    saveConfig(cfg){localStorage.setItem(STORE_KEY,JSON.stringify({url:String(cfg.url||'').trim(),anonKey:String(cfg.anonKey||'').trim()}));return init();},
    client(){return client||init();},
    configured(){return !!this.client();},
    async test(){const c=this.client();if(!c)throw new Error('URL atau publishable/anon key belum diisi, atau SDK tidak termuat.');const {error}=await c.from('channels').select('id',{head:true,count:'exact'});if(error)throw error;return true;},
    async signUp(email,password,displayName){const c=this.client();if(!c)throw new Error('Atur koneksi Supabase terlebih dahulu.');return c.auth.signUp({email,password,options:{data:{display_name:displayName}}});},
    async signIn(email,password){const c=this.client();if(!c)throw new Error('Atur koneksi Supabase terlebih dahulu.');return c.auth.signInWithPassword({email,password});},
    async signOut(){const c=this.client();if(c)return c.auth.signOut();},
    async session(){const c=this.client();if(!c)return null;const {data,error}=await c.auth.getSession();if(error)throw error;return data.session;},
    async user(){const c=this.client();if(!c)return null;const {data,error}=await c.auth.getUser();if(error)throw error;return data.user||null;},
    async listChannels(){const c=this.client();if(!c)return null;const {data,error}=await c.from('channels').select('id,owner_id,name,slug,description,category,icon,privacy,created_at').eq('privacy','public').eq('status','active').order('created_at',{ascending:false});if(error)throw error;return (data||[]).map(x=>({id:x.id,name:x.name,category:x.category,desc:x.description,followers:0,icon:x.icon||'✦',cover:'cover-talk',verified:false,featured:false,ownerId:x.owner_id,privacy:x.privacy,slug:x.slug}));},
    async createChannel(input){const c=this.client();if(!c)throw new Error('Atur koneksi Supabase terlebih dahulu.');const {data:userResult,error:userError}=await c.auth.getUser();if(userError)throw userError;if(!userResult.user)throw new Error('Silakan masuk dengan akun Supabase terlebih dahulu.');const slug=(input.name||'channel').toLowerCase().normalize('NFKD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')+'-'+Date.now().toString(36);const payload={owner_id:userResult.user.id,name:input.name,slug,description:input.description||'',category:input.category||'Komunitas',icon:input.icon||'✦',privacy:input.privacy||'public'};const {data,error}=await c.from('channels').insert(payload).select().single();if(error)throw error;return {id:data.id,name:data.name,category:data.category,desc:data.description,followers:0,icon:data.icon,cover:'cover-talk',verified:false,featured:false,ownerId:data.owner_id,privacy:data.privacy,slug:data.slug};},
    async listPosts(){const c=this.client();if(!c)return null;const {data,error}=await c.from('posts').select('id,channel_id,author_id,body,media_url,created_at,channels(name,icon),post_reactions(count),comments(count)').eq('status','published').order('created_at',{ascending:false}).limit(100);if(error)throw error;return (data||[]).map(x=>({id:x.id,channelId:x.channel_id,author:x.channels?.name||'Channel',icon:x.channels?.icon||'✦',time:new Date(x.created_at).toLocaleString('id-ID'),text:x.body,likes:x.post_reactions?.[0]?.count||0,comments:x.comments?.[0]?.count||0,kind:x.media_url?'image':'post',image:''}));},
    async createPost(input){const c=this.client();if(!c)throw new Error('Atur koneksi Supabase terlebih dahulu.');const {data:userResult,error:userError}=await c.auth.getUser();if(userError)throw userError;if(!userResult.user)throw new Error('Silakan masuk dengan akun Supabase terlebih dahulu.');const {data,error}=await c.from('posts').insert({channel_id:input.channelId,author_id:userResult.user.id,body:input.body,media_url:input.mediaUrl||null,status:'published'}).select().single();if(error)throw error;return data;},
    async follow(channelId,userId){const c=this.client();if(!c)throw new Error('Atur koneksi Supabase terlebih dahulu.');const {error}=await c.from('channel_followers').insert({channel_id:channelId,user_id:userId});if(error&&error.code!=='23505')throw error;return true;},
    async unfollow(channelId,userId){const c=this.client();if(!c)throw new Error('Atur koneksi Supabase terlebih dahulu.');const {error}=await c.from('channel_followers').delete().eq('channel_id',channelId).eq('user_id',userId);if(error)throw error;return true;},
    async like(postId,userId){const c=this.client();if(!c)throw new Error('Atur koneksi Supabase terlebih dahulu.');const {error}=await c.from('post_reactions').upsert({post_id:postId,user_id:userId,reaction:'like'},{onConflict:'post_id,user_id'});if(error)throw error;return true;},
    async unlike(postId,userId){const c=this.client();if(!c)throw new Error('Atur koneksi Supabase terlebih dahulu.');const {error}=await c.from('post_reactions').delete().eq('post_id',postId).eq('user_id',userId);if(error)throw error;return true;},
    async comment(postId,body){const c=this.client();if(!c)throw new Error('Atur koneksi Supabase terlebih dahulu.');const {data:userResult,error:userError}=await c.auth.getUser();if(userError)throw userError;if(!userResult.user)throw new Error('Silakan masuk terlebih dahulu.');const {data,error}=await c.from('comments').insert({post_id:postId,author_id:userResult.user.id,body}).select().single();if(error)throw error;return data;}
  };
  init();
})();
