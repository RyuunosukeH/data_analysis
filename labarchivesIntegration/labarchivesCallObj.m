classdef labarchivesCallObj 
    % Class for communicating with the labarchives electronic laboratory
    % notbook system using the API.
    %
    % obj = labarchivesCallObj returns a labarchives call object which can
    % be used to interact with a lab archives notebook. By default, the
    % object will connect to the notebook Data, folder given by the year
    % yyyy (e.g. 2020), page yyyy-MM-dd (e.g. 2020-02-03). The call object
    % uses the 'sgrlab' credentials.
    % 
    % obj = labarchivesCallObj(name1,value1,name2,value2,...) will
    % use the optional arguments to load the requested notebook, folder, or
    % page, replacing the defaults as needed. Currently accepted parameters
    % include:
    % 
    % 
    % 'notebook', a string of the name of the active notebook (The default
    % is '2D-IR Data'); 
    %
    % 'folder', a string of the name of the active folder
    % (Default is the current four digit year, e.g. '2020');
    %
    % 'page', a string of the name of the active page. (Default is a date
    % string of the year, month, and day, e.g. '2020-02-05', generated by
    % datetime('today','format','yyyy-MM-dd') [or
    % datestr(now,'yyyy-mm-dd') for older matlab versions]
    % 
    % 'uid', a string of the unique (secret) user id key created by
    % labarchives. Do not share or post these keys for security.
    %
    % 'akid', the University's access key ID (unique name)
    %
    % 'access_password', the University's password
    %
    %
    % METHODS: A few important methods are
    % 
    % obj.addAttachment('fname') uploads the file fname to the current page
    %
    % obj.addEntry(entry_type,entry_data) adds an entry with text as data.
    % Entry type is 'heading', 'plain text entry', or 'text entry' (rich
    % text). entry_data is any text string.
    %
    % obj.downloadAttachments(file_name), where file_name is a string or a
    % cell of strings. Files are stored in the current working directory.
    %
    % obj.saveSecretKeys will store the credentials in
    % LABARCHIVES_SECRET_KEYS.mat in the matlab path so future access does
    % not require single-sign-on, two-factor authentication, and
    % copy-pasting the temporary password.
    %
    %
    % EXAMPLES:
    %
    % To connect with default behavior, which is good for automatic data
    % uploads:
    %
    % obj = labarchivesCallObj; 
    %
    % To connect with credentials from the command line, often for first
    % time connections:
    %
    % akid = 'XXXXXXXXX';
    % access_password = 'YYYYYY';
    % LAuser = 'YOU@pitt.edu'; %<==== update this
    % LApw = '';%<====== paste LA App password here 
    %
    % obj = labarchivesCallObj('akid',akid,'access_password',access_password,...
    %     'user',LAuser,'password',LApw);
    %
    %
    % Here's a link to the LA current API documentation: 
    % https://mynotebook.labarchives.com/share/LabArchives%20API/NS4yfDI3LzQvVHJlZU5vZGUvMzU0MzQ4ODY0M3wxMy4y
    %
    properties
        %stored in secret file (don't upload to github!)
        akid; %institution's access key ID (from LA)
        access_password; %institution's password (from LA)
        uid; %credentials of the current user
        
        % LA communication settings
        hash_method = 'SHA-1'; %hash for communications
        base_url = 'https://api.labarchives.com'; %labarchives URI
        
        % notebook information
        user_name; %name corresponding to the uid
        notebooks; %structure of available notebooks
        notebook_name; %current notebook, default '2D-IR Data'
        nid; %notebook id for API calls
        folder_name; %active folder string, default generated by year
        fid;%active folder id
        page_name; %active page string, default generated by the date
        pid;%active page id
        entries; %structure of entries on the current page
        
        % low level variables for talking to LA
        epoch_offset = 0;%a magic number should be about 1.8e7
        api_class;%string of the API class called (see LA documentation)
        api_method_called; %the name of the api method 
        api_method_specific; %additional parameters
        call_string;%assembled API string 
        authentication_string; %a verification, authencation string
        rest_call_string;%total string for the REST call
        response;%return from the REST call
    end
    properties (Hidden)
        secret_file='LABARCHIVES_SECRET_KEYS.mat';%location of secret keys
    end
    
    methods
        function obj = labarchivesCallObj(varargin)
            %construct the labarchives call object 
            
            %load akid, access_password, and uid from secret file if it exists
            obj = loadSecretKeys(obj);
                
            %set default page and folder names based on year and date
            obj.notebook_name = '2D-IR Data';
            obj.folder_name = sprintf('%s',datestr(now,'yyyy'));
            obj.page_name = sprintf('%s',datestr(now,'yyyy-mm-dd'));            
            %obj.folder_name = sprintf('%s',datetime('today','Format','yyyy'));
            %obj.page_name = sprintf('%s',datetime('today','Format','yyyy-MM-dd'));

            %vars for if we are setting up the uid
            LAuser = '';
            LApassword = '';
            
            %parse the input arguments (if any)
            while length(varargin)>=2
                arg = varargin{1};
                val = varargin{2};
                switch lower(arg)
                    case 'notebook'
                        obj.notebook_name = val;
                    case 'folder'
                        obj.folder_name = val;
                    case 'page'
                        obj.page_name = val;
                    case 'uid'
                        obj.uid = val;
                    case 'akid'
                        obj.akid = val;
                    case 'access_password'
                        obj.access_password = val;
                    case 'user'
                        LAuser = val;
                    case 'password'
                        LApassword = val;
                    otherwise
                        error(['labarchivesCallObj(): unknown option ',arg])
                end
                varargin = varargin(3:end);
            end       
            
            % if we have both akid and access_password (not empty) get the
            % epoch time set up properly
            if ~isempty(obj.akid)&&~isempty(obj.access_password)
                %correct the weird LA time offset by measuring the
                %difference between matlab's time and LA's reported time
                
                % get time reported by matlab (now), convert to time since
                %1970 UTC, convert s to ms, and finally make sure it is an
                %integer
                matlab_time = obj.timeSinceEpochMiliseconds;%round(posixtime(datetime('now'))*1000);
                
                % get LA reported time
                labarchives_time = obj.getEpochTime;
                
                % the difference
                obj.epoch_offset = labarchives_time - matlab_time;
            end
            
            % if both username and password were input from the command
            % line then try to load the uid
            if ~isempty(LAuser)&&~isempty(LApassword)
                obj = obj.loadUid(LAuser,LApassword);
            end
            
            % if we have a uid load what we can
            if ~isempty(obj.uid)
                obj = obj.loadUserInfoByUid;
                disp('connected to labarchives');
                
                %load the notebook
                obj = obj.loadNid;
                
                %load the folder
                obj = obj.loadFolder;
                
                %load the page
                obj = obj.loadPage;
                
                %load the current entries
                obj = obj.loadEntriesForPage;
            end
        end
        
        function obj = buildCallString(obj)
            %assemble the API call from class, method, and method specific
            %elements
            obj.call_string = [obj.api_class obj.api_method_called '?' obj.api_method_specific];
        end
        
        function obj = buildRestCallString(obj)
            %assemble the REST call from the API class and method and the
            %authentication strings
            if strcmp(obj.call_string(end),'?')
                delim = '';
            else
                delim = '&';
            end
            
           obj.rest_call_string = [obj.base_url '/' obj.call_string delim obj.authentication_string];
        end
        
        function obj = buildAuthenticationString(obj,varargin)
            %construct an authentication string 
            %
            %The authentication protocol requires an HMAC hash of the
            %message using the access_password and an expiration date for
            %the request. Note there is a weird time offset that
            %epoch_offset deals with. See LA documentation for details.
            %
            %Example
            %    obj = obj.buildAuthenticationString;
            %Also 
            %    obj = obj.buildAuthenticationString(string);
            %
            %expires = round(posixtime(datetime('now'))*1000 + obj.epoch_offset);
            expires = obj.timeSinceEpochMiliseconds + obj.epoch_offset;
            if isempty(varargin)
                string_to_encode = [obj.akid obj.api_method_called num2str(expires)];
            else
                string_to_encode = [obj.akid varargin{1} num2str(expires)];
            end                
            sig = urlencode(HMAC_sgr(obj.access_password,string_to_encode,obj.hash_method));

            obj.authentication_string = sprintf('akid=%s&expires=%i&sig=%s',obj.akid,expires,sig);

        end
        
        function obj = executeRestCall(obj)
            % send the REST call using webread. 
            %
            % The result of the webread (usually xml) is stored
            % in obj.response, which probably needs further processing with
            % responseXml2Struct.
            obj.response = webread(obj.rest_call_string);
        end
                 
        function obj = responseXml2Struct(obj)
            %convert obj.response from XML to a structure
            obj.response = xmlstring2struct(obj.response);
        end
        
        function callObj = loadResponse(callObj)
            %workhorse method to communicate with LA
            callObj = callObj.buildCallString;
            callObj = callObj.buildAuthenticationString;
            callObj = callObj.buildRestCallString;
            callObj = callObj.executeRestCall;
            callObj = callObj.responseXml2Struct;

        end
        
        function out = getEpochTime(callObj)
            %get LA's current time
            callObj.api_class = 'api/utilities/';
            callObj.api_method_called = 'epoch_time';
            callObj.api_method_specific = '';
            
            callObj = callObj.loadResponse;
            %
            out = str2double(callObj.response.utilities.epoch_dash_time.Text);
        end
        
        function callObj = loadUid(callObj,user,password)
            %obtain the uid from a username and password combo
            callObj.api_class = 'api/users/';
            callObj.api_method_called = 'user_access_info';
            callObj.api_method_specific = ['login_or_email=' user '&password=' password];
            
            
            callObj = callObj.loadResponse;

            callObj.uid = callObj.response.users.id.Text;
            
            callObj = callObj.attachNotebooks;
        end
        
        function nid = getNidByName(callObj,name)
            %get the notebook id of a named notebook
            %Example:
            %    nid = getNidByName(callObj,name)
            n = length(callObj.notebooks);
            for ii = 1:n
                if strcmp(name,callObj.notebooks(ii).name.Text)
                    nid  = callObj.notebooks(ii).id.Text;
                end
            end
        end
        
        function obj = loadNid(obj)
            %get the notebook id of the current notebook
            %Example:
            %    callObj = getNidByName(callObj)
            obj.nid = obj.getNidByName(obj.notebook_name);
        end
        
        function callObj = attachNotebooks(callObj)
            % attach a structure of the notebooks available to user
            n=length(callObj.response.users.notebooks.notebook);
            callObj.notebooks = callObj.response.users.notebooks.notebook{1};
            for ii = 2:n
                callObj.notebooks(ii) = callObj.response.users.notebooks.notebook{ii};
            end

        end
        
        function obj = loadUserInfoByUid(obj)
            %get user information associated with the current uid
            obj.api_class = 'api/users/';
            obj.api_method_called = 'user_info_via_id';
            obj.api_method_specific = sprintf('uid=%s',obj.uid);

            obj = obj.loadResponse;
            obj.user_name = obj.response.users.email.Text;
            obj = obj.attachNotebooks;
        end
        
        function s = getMaxFileSize(callObj)
            %get the largest file upload allowed
            callObj.api_class = 'api/users/';
            callObj.api_method_called = 'max_file_size';
            callObj.api_method_specific = sprintf('uid=%s',callObj.uid);

            callObj = callObj.loadResponse;
            s = callObj.response.users.max_dash_file_dash_size.Text;
%             fprintf(1,'max file size = %s\n',s);
            s = str2double(s);
        end
        
        function tree = getTreeInfo(callObj,level)
            %low level function to traverse the file tree structure
            callObj.api_class = 'api/tree_tools/';
            callObj.api_method_called = 'get_tree_level';
            callObj.api_method_specific = ...
                sprintf('uid=%s&nid=%s&parent_tree_id=%s',...
                callObj.uid,callObj.nid,num2str(level));

            callObj = callObj.loadResponse;
            if isfield(callObj.response.tree_dash_tools.level_dash_nodes,'level_dash_node')
                tree = callObj.response.tree_dash_tools.level_dash_nodes.level_dash_node;
            elseif isfield(callObj.response.tree_dash_tools.level_dash_nodes,'Text')
                tree = callObj.response.tree_dash_tools.level_dash_nodes.Text;
            end
        end
        
        function tree_id = getFolderByName(obj,name)
            %get the id of a named folder in the current notebook
            node_exist = false;
            
            %get the info we can about the data folder
            tree = getTreeInfo(obj,0); %search at root level 0 only
            if ~iscell(tree),tree = {tree};end
            try
                for ii = 1:length(tree)
                    if strcmp(tree{ii}.display_dash_text.Text,name)
                        tree_id = tree{ii}.tree_dash_id.Text;
                        node_exist = true;
                        break;%we found it so leave
                    end
                end
            catch
                fprintf(1,'did not find folder %s\n',name);
            end
            
            if node_exist
                %say we found it
                fprintf(1,'found folder %s > %s\n',...
                    obj.notebook_name,name);
            else
                %we went through the list and didn't find the page (or list
                %was empty) so make page
                fprintf(1,'add folder %s > %s  ...\n',...
                    obj.notebook_name,name);
                %add a node a the root level, true=folder
                obj = obj.insertNode(obj.uid,obj.nid,'0',name,true);
                tree_id = obj.response.tree_dash_tools.node.tree_dash_id.Text;
                                
                %move it to the top of the list
                obj.updateNode(obj.uid,obj.nid,tree_id,'node_position','0');
            end        
      
        end
        
        function obj = loadFolder(obj)
            %get the id of the current folder
            obj.fid = obj.getFolderByName(obj.folder_name);
            
        end
        
        function obj = loadPage(obj)
            %get the page id of the current page
            name = obj.page_name;
            
            page_exist = false;
            %get the info we can about the data folder
            tree = obj.getTreeInfo(obj.fid);
            if ~iscell(tree),tree = {tree};end
            if isstruct(tree{1}) %if we didn't get an empty response
                for ii = 1:length(tree)
                    if strcmp(tree{ii}.display_dash_text.Text,name)
                        obj.pid = tree{ii}.tree_dash_id.Text;
                        page_exist = true;
                        break;%we found it so leave
                    end
                    
                end
            end
            if page_exist
                %say we found it
                fprintf(1,'found page %s > %s > %s\n',...
                    obj.notebook_name,obj.folder_name,obj.page_name);
            else
                %we went through the list and didn't find the page (or list
                %was empty) so make page
                fprintf(1,'add page %s > %s > %s ...\n',...
                    obj.notebook_name,obj.folder_name,obj.page_name);
                obj = obj.insertNode(obj.uid,obj.nid,obj.fid,obj.page_name,false);
                obj.pid = obj.response.tree_dash_tools.node.tree_dash_id.Text;
                
                % insert entry template when page is created
                obj.insertEntryTemplate;
            end        
            
            
        end
        
        function callObj = insertNode(callObj,uid,nid,fid,name,isFolderBoolean)
            %insert (create) a page or folder
            %
            %callObj = insertNode(callObj,uid,nid,fid,name,isFolderBoolean)
            %
            %where uid is the user id, nid is the notebook id, fid is the
            %folder id, name is the name of the new folder or page, and
            %isFolderBoolean is true for a folder and false for a page.
            
            if isFolderBoolean
                is_folder_string = 'true';
            else
                is_folder_string = 'false';
            end
         
            callObj.api_class = 'api/tree_tools/';
            callObj.api_method_called = 'insert_node';
            callObj.api_method_specific = ...
                sprintf('uid=%s&nid=%s&parent_tree_id=%s&display_text=%s&is_folder=%s',...
                uid,nid,fid,name,is_folder_string);

            callObj = callObj.loadResponse;
            
        end
        
        function callObj = updateNode(callObj,uid,nid,tree_id,varargin)
            %update information about a page or folder
            %
            %callObj = updateNode(callObj,uid,nid,tree_id,'parent_tree_id',val)
            % moves the node nid to be contained by parent_tree_id val (0 is
            % root).
            %callObj =
            %updateNode(callObj,uid,nid,tree_id,'display_text',val) changes
            %the name to val.
            %callObj = updateNode(callObj,uid,nid,tree_id,'node_position',val)
            %changes the order of displaying the item. 0 is the top; set to
            %a large value like 1000 to move to the bottom of the list.

            
            callObj.api_class = 'api/tree_tools/';
            callObj.api_method_called = 'update_node';
            callObj.api_method_specific = ...
                sprintf('uid=%s&nid=%s&tree_id=%s',...
                uid,nid,tree_id);

            while length(varargin)>=2
                arg = varargin{1};
                val = varargin{2};
                switch lower(arg)
                    case 'parent_tree_id'
                        callObj.api_method_specific = [callObj.api_method_specific sprintf('&parent_tree_id=%s',val)];
                    case 'display_text'
                        callObj.api_method_specific = [callObj.api_method_specific sprintf('&display_text=%s',val)];
                    case 'node_position'
                        callObj.api_method_specific = [callObj.api_method_specific sprintf('&node_position=%s',val)];
                    otherwise
                        error(['labarchivesCallObj.updateNode: unknown option ',arg])
                end
                varargin = varargin(3:end);
            end       

            callObj = callObj.loadResponse;
            
        end
        
        function obj = addEntry(obj,part_type,entry_data)
            %add a text entry or header
            %
            %obj = addEntry(obj,part_type,entry_data)
            %part_type can be 'text entry' (rich text), 'plain text entry'
            %(recommended for markdown), or 'heading'. Entry_data is any
            %text string.
            
            %part_type = 'text entry';
            %entry_data = 'hello world!';
            
            % these should be updated for each call
            obj.api_class = 'api/entries/';
            obj.api_method_called = 'add_entry';
            obj.api_method_specific = sprintf('uid=%s&nbid=%s&pid=%s',...
                obj.uid,obj.nid,obj.pid);

            obj = obj.buildCallString;
            obj = obj.buildAuthenticationString;
            obj = obj.buildRestCallString;
            %obj = obj.executeRestCall;

            
            obj.response = webwrite(obj.rest_call_string,...
                'part_type',part_type,'entry_data',entry_data);

            obj = obj.responseXml2Struct;

        end
        
        function obj = addAttachment(obj,filename)
            % attach a file to the current page
            %
            % obj = obj.addAttachment('fname.mat')
            %
            % attaches file fname.mat to the current page.
            
            %filename = 'test_file_to_add.m';
            opt = weboptions('MediaType','application/octet-stream');
            
            %load file contents
            ffid = fopen(filename);
            file_contents = fread(ffid,'*char');
            fclose(ffid);
            
            % these should be updated for each call
            obj.api_class = 'api/entries/';
            obj.api_method_called = 'add_attachment';
            obj.api_method_specific = ...
                sprintf('uid=%s&nbid=%s&pid=%s&filename=%s',...
                obj.uid,obj.nid,obj.pid,filename);
            
            obj = obj.buildCallString;
            obj = obj.buildAuthenticationString;
            obj = obj.buildRestCallString;

            tmp = dir(filename);
            maxfs = obj.getMaxFileSize;
            if tmp.bytes > maxfs
                warning('Skip: File %s size %f > %f (max file size)',filename,tmp.bytes,maxfs);
                obj.response = [];
                return
            end
            
            obj.response = webwrite(obj.rest_call_string,file_contents,opt);

            obj = obj.responseXml2Struct;

        end
        
        function obj = updateAttachment(obj,filename)
            % update a file on the current page
            %
            % obj = obj.updateAttachment('fname.mat')
            %
            % updates file fname.mat on the current page.
            
            %filename = 'test_file_to_add.m';
            opt = weboptions('MediaType','application/octet-stream');
            
            %load file contents
            ffid = fopen(filename);
            file_contents = fread(ffid,'*char');
            fclose(ffid);
            
            % load the current page entries
            obj = obj.loadEntriesForPage();
            
            % initialize an empty array for entry id
            eid = [];
            
            % search for the entry with the same name as the input filename
            % and return the entry id of that file.
            if length(obj.entries) == 1
                if strcmp(obj.entries.attach_dash_file_dash_name.Text, filename)
                    eid = obj.entries.eid.Text;
                end
            else
                for ii = 1:length(obj.entries)
                    if strcmp(obj.entries{ii}.attach_dash_file_dash_name.Text, filename)
                        eid = obj.entries{ii}.eid.Text;
                    end
                end
            end
            
            % if the entry id is not empty follow this procedure to update
            % the file uploaded to the entry
            if ~isempty(eid)
                % these should be updated for each call
                obj.api_class = 'api/entries/';
                obj.api_method_called = 'update_attachment';
                obj.api_method_specific = ...
                    sprintf('uid=%s&eid=%s&filename=%s',...
                    obj.uid,eid,filename);

                obj = obj.buildCallString;
                obj = obj.buildAuthenticationString;
                obj = obj.buildRestCallString;

                tmp = dir(filename);
                maxfs = obj.getMaxFileSize;
                if tmp.bytes > maxfs
                    warning('Skip: File %s size %f > %f (max file size)',filename,tmp.bytes,maxfs);
                    obj.response = [];
                    return
                end

                obj.response = webwrite(obj.rest_call_string,file_contents,opt);

                obj = obj.responseXml2Struct;
            else
                % if the entry id (eid) is empty then none of the entries were
                % found to have the same filename as the input filename and
                % the function will just upload the file as a new entry.
                obj.addAttachment(filename);
            end

        end
        
        function obj = insertEntryTemplate(obj)
            %upload the template for a 2D-IR experiment to current page
            
            part_type = 'plain text entry';
            
            username = char(java.lang.System.getProperty('user.name'));
            hostname = char(java.net.InetAddress.getLocalHost.getHostName);
            entry_header = sprintf('# %s\n',obj.page_name);
            %entry_empty_line = newline; %just an empty line\n
            entry_empty_line = sprintf('\n'); %just an empty line\n
            entry_body = sprintf(['## Experiment info\n\n'...
                '**Experimenter:** \n\n'...
                '**Sample(s):** (solute / solvent, path length, O.D., temperature, ...) \n\n'...
                '**What else?:** \n\n'...
                '## Scientific goals for these experiments: \n\n\n'...
                '## Other relevant experiments: \n\n\n'...
                '## Relevant literature: \n'...
                '[Brinzer 2015](https://doi.org/10.1063/1.4917467) as an example...\n'...
                '## Experimental plans: \n\n\n'...
                '## Standard experimental setup: \n'...
                '`[X]` Pump-Probe 2D-IR\n'...
                '`[X]` XXXX Polarization\n'...
                '`[ ]` XXYY Polarization\n'...
                '`[ ]` Temperature dependent study\n'...
                '`[ ]` Pump-probe anisotropy measurement\n'...
                '## Modifications to experimental setup: \n\n'...
                '## FTIR:\n'...
                'Pre:\n'...
                'Post:\n'...
                '## Location of data analysis:\n'...
                ]);
            entry_footer = sprintf(['_Entry generated automatically by '...                
                'M-file %s.m_\n_%s@%s logged in as %s_\n[Click here for Markdown basics]'...
                '(https://labarchives.kayako.com/Knowledgebase/Article/View/426/0/409-plain-text)'],...
                mfilename,username,hostname,obj.user_name);
            
            entry_data = [entry_header entry_empty_line entry_body entry_empty_line entry_footer];
            obj = obj.addEntry(part_type,entry_data);
            
            part_type = 'heading';
            entry_data = 'FTIR';
            obj = obj.addEntry(part_type,entry_data);
                
            part_type = 'heading';
            entry_data = 'Data aquisition scripts';
            obj = obj.addEntry(part_type,entry_data);
            
            part_type = 'heading';
            entry_data = 'Data analysis scripts';
            obj = obj.addEntry(part_type,entry_data);

            part_type = 'heading';
            entry_data = 'Data files and experimental observations';
            obj = obj.addEntry(part_type,entry_data);

        end
    
        function [obj,entries] = getEntriesForPage(obj,uid,nid,pid)
            entries = '';
            %get information about all the entries on the given page
            obj.api_class = 'api/tree_tools/';
            obj.api_method_called = 'get_entries_for_page';
            obj.api_method_specific = ...
                sprintf('uid=%s&page_tree_id=%s&nbid=%s',...
                uid,pid,nid);
            obj=obj.loadResponse;
            if isfield(obj.response.tree_dash_tools.entries,'entry')
                entries = obj.response.tree_dash_tools.entries.entry;
            end
        end
        
        function obj = loadEntriesForPage(obj)
            %get the entries for the current page
            [obj,obj.entries] = getEntriesForPage(obj,obj.uid,obj.nid,obj.pid);
        end
        
        function [obj,eids] = getAttachmentsByName(obj,entries,attachments)
            %search through entries for attachments by file name
            
            eids = cell(size(attachments));
            for jj=1:length(attachments)
                attachment_name = attachments{jj};
                
                attachment_exist = false;
                %get the info we can about the data folder
                if ~iscell(entries),entries = {entries};end
                if isstruct(entries{1}) %if we didn't get an empty response
                    for ii = 1:length(entries)
                        if strcmp(entries{ii}.attach_dash_file_dash_name.Text,attachment_name)
                            attachment_exist = true;
                            eid = entries{ii}.eid.Text;
                            break;%we found it so leave
                        end
                        
                    end
                end
                if attachment_exist
                    %say we found it
                    fprintf(1,'found attachment %s > %s > %s > %s\n',...
                        obj.notebook_name,obj.folder_name,obj.page_name,attachment_name);
                    fprintf(1,'    file %s eid=%s\n',attachment_name,eid);
                    
                    %download it
                    %fprintf(1,'    download %s eid=%s\n',attachment_name,eid);
                    
                    %save the eid
                    eids{jj} = eid;
                else
                    %we went through the list and didn't find the attachment
                    fprintf(1,'**did not locate %s > %s > %s > %s**\n',...
                        obj.notebook_name,obj.folder_name,obj.page_name,attachment_name);
                end
            end 
        end
        
        function obj = downloadAttachments(obj,attachments)
            %download the named attachments for the *current* page
            
            %make sure the 
            if ~iscell(attachments),attachments ={attachments};end
            
            %refresh the entries list
            obj = obj.loadEntriesForPage;
            
            %get the eid for each file
            [obj,eids] = getAttachmentsByName(obj,obj.entries,attachments);
            
            %prepare
            obj.api_class = 'api/entries/';
            obj.api_method_called = 'entry_attachment';

            for ii = 1:length(eids)
                eid = eids{ii};
                
                %skip files we didn't find
                if isempty(eid),continue,end
                
                %prepare to download files
                fprintf(1,'get file %s eid=%s\n',attachments{ii},eid);
                obj.api_method_specific = ...
                    sprintf('uid=%s&eid=%s',...
                    obj.uid,eid);
                obj = obj.buildCallString;
                obj = obj.buildAuthenticationString;
                obj = obj.buildRestCallString;
                
                %get data                
                obj = obj.executeRestCall;
                
                %write it to a file
                fid_ = fopen(attachments{ii},'wb');
                fwrite(fid_,obj.response,'uint8');
                fclose(fid_);
            end
        end
        
        function obj=downloadRuns(obj,runs)
            %download files assuming yyyy-MM-dd-001.mat run number format.
            %example
            %        obj=obj.downloadRuns([1:5,17])
            % would download runs 1-5 and 17 from the current page assuming
            % the file names are the same as the page name (yyyy-MM-dd)
            % followed by the run numbers (the way file names are formed by
            % the spectrometer software).

            attachments = cell(size(runs));
            for ii = 1:length(runs)
                attachments{ii}=sprintf('%s-%03i.mat',obj.page_name,runs(ii));
            end
            obj = obj.downloadAttachments(attachments);
        end
        
        function obj=loadSecretKeys(obj)
            %load the akid, access_password, and uid from LABARCHIVES_SECRET_KEYS.mat
            %
            %load the secret keys file with variables uid, akid, and
            %access_password. These credentials can be loaded by
            %so single-sign-on, two-factor authentication,
            %and copy/pasting LA access pw is not necessary. The secret key
            %file must be on the matlab path.
            if exist(obj.secret_file,'file')
                m = load(obj.secret_file);
                if isfield(m,'uid')
                    obj.uid = m.uid;
                end
                if isfield(m,'akid')
                    obj.akid = m.akid;
                end
                if isfield(m,'access_password')
                    obj.access_password = m.access_password;
                end
            else
                fprintf(1,'failed to find labarchives secret key file %s on matlab path.\n',obj.secret_file);
            end
        end
        
        function saveSecretKeys(obj)
            %save current keys to LABARCHIVES_SECRET_KEYS.mat
            %
            %generate a secret keys file with variables uid, akid, and
            %access_password. These credentials can be loaded by
            %loadSecretKeys so single-sign-on, two-factor authentication,
            %and copy/pasting LA access pw is not necessary.
            %
            %the secret keys file is placed in the first directory returned
            %by userpath().
            
            %get the default user path, split on ':'s (or default path
            %separator) if there is more than one directory
            str = regexp(userpath,pathsep,'split');
            
            %take the first, should be $home/Documents/MATLAB
            path = str{1};
            
            full_file_name = fullfile(path,obj.secret_file);
            
            %don't ask why I have to do it like this... I don't get it.
            s=struct('uid',obj.uid,'akid',obj.akid,'access_password',obj.access_password);
            save(full_file_name,'-struct','s','uid','akid','access_password');
        end
    end
    methods(Static)
      function t = timeSinceEpochMiliseconds
        t = round(etime(clock,datevec(datenum(1970,1,1,0,0,0))))*1000;
      end
    end
end
