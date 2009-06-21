" Copyright (C) 2009 Romain Bignon
"
" This program is free software; you can redistribute it and/or modify
" it under the terms of the GNU General Public License as published by
" the Free Software Foundation, version 3 of the License.
"
" This program is distributed in the hope that it will be useful,
" but WITHOUT ANY WARRANTY; without even the implied warranty of
" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
" GNU General Public License for more details.
"
" You should have received a copy of the GNU General Public License
" along with this program; if not, write to the Free Software
" Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
"
" Maintainer:   Romain Bignon
" Contributor:  Adam Schmalhofer
" URL:          http://symlink.me/wiki/blogit
" Version:      1.1
" Last Change:  2009 June 21
"
" Commands :
" ":Blogit ls"
"   Lists all articles in the blog
" ":Blogit new"
"   Opens page to write new article
" ":Blogit edit <id>"
"   Opens the article <id> for edition
" ":Blogit commit"
"   Saves the article to the blog
" ":Blogit push"
"   Publish article
" ":Blogit unpush"
"   Unpublish article
" ":Blogit rm <id>"
"   Remove an article
" ":Blogit categories" or ":Blogit cat"
"   Show categories list
" ":Blogit tags"
"   Show tags list
" ":Blogit help"
"   Display help
"
" Configuration :
"   Create a file called passwords.vim somewhere in your 'runtimepath'
"   (preferred location is "~/.vim/"). Don't forget to set the permissions so
"   only you can read it. This file should include:
"
"       let blogit_username='Your blog user name'
"       let blogit_password='Your blog password. Not the API-key.'
"       let blogit_url='http://your.path.to/xmlrpc.php'
"
"   In addition you can set these settings in your vimrc:
"
"       let blogit_tags=0
"
"   This deactivates the use of tags. It is needed if your WordPress doesn't
"   have the UTW-RPC[3] plugin installed (WordPress.com does).
"
"       let blogit_unformat='pandoc --from=html --to=rst --reference-links'
"       let blogit_format='pandoc --from=rst --to=html --no-wrap'
"
"   The blogit_format and blogit_unformat each contain a shell command to
"   filter the blog entry text (no meta data) before a commit and after an
"   edit, respectively. In the example we use pandoc[1] to edit the blog in
"   reStructuredText[2].
"
"   If you have multible blogs replace 'blogit' in 'blogit_username' etc. by a
"   name of your choice (e.g. 'your_blog_name') and use:
"
"       let blog_name='your_blog_name'
"   or
"       let b:blog_name='your_blog_name'
"
"   to switch between them.
"
" Usage :
"   Just fill in the blanks, do not modify the highlighted parts and everything
"   should be ok.
"
"   gf or <enter> in the ':Blogit ls' buffer edits the blog post in the
"   current line.
"
"   Categories and tags can be omni completed via *compl-function* (usually
"   CTRL-X_CTRL-U) once the list of them is gotten via ":Blogit cat[egories]"
"   and ":Blogit tags".
"
" [1] http://johnmacfarlane.net/pandoc/
" [2] http://docutils.sourceforge.net/docs/ref/rst/introduction.html
" [3] http://blog.circlesixdesign.com/download/utw-rpc-autotag/
"
" vim: set et softtabstop=4 cinoptions=4 shiftwidth=4 ts=4 ai

runtime! passwords.vim
command! -nargs=* Blogit exec('py blogit.command(<f-args>)')

let s:used_categories = []
let s:used_tags = []

function CompleteCategories(findstart, base)
    " based on code from :he complete-functions
    if a:findstart
        " locate the start of the word
        let line = getline('.')
        let start = col('.') - 1
        while start > 0 && line[start - 1] =~ '\a'
            let start -= 1
        endwhile
        return start
    else
        if getline('.') =~? '^Categories: '
            let L = s:used_categories
        elseif getline('.') =~? '^Tags: '
            let L = s:used_tags
        else
            return []
        endif
	    let res = []
	    for m in L
	        if m =~ '^' . a:base
		        call add(res, m . ', ')
	        endif
	    endfor
	    return res
    endif
endfunction

python <<EOF
# -*- coding: utf-8 -*-
import vim, xmlrpclib, sys, re
from time import mktime, strptime, strftime, localtime, gmtime
from calendar import timegm
from subprocess import Popen, CalledProcessError, PIPE
from xmlrpclib import DateTime, Fault
from types import MethodType

#####################
# Do not edit below #
#####################

class BlogIt:
    class FilterException(Exception):
        def __init__(self, message, input_text, filter):
            self.message = "Blogit: Error happend while filtering with:" + \
                    filter + '\n' + message
            self.input_text = input_text
            self.filter = filter

    def __init__(self):
        self.client = None
        self.post = {}

    def connect(self):
        self.client = xmlrpclib.ServerProxy(self.blog_url)

    def get_current_post(self):
        try:
            return self.post[vim.current.buffer.number]
        except KeyError:
            return None

    def set_current_post(self, value):
        self.post[vim.current.buffer.number] = value

    current_post = property(get_current_post, set_current_post)

    def command(self, command='help', *args):
        if self.client is None:
            self.connect()
        try:
            getattr(self, 'command_' + command)(*args)
        except AttributeError:
            sys.stderr.write("No such command: %s" % command)
        except TypeError, e:
            try:
                sys.stderr.write("Command %s takes %s arguments" % \
                        (command, int(str(e).split(' ')[3]) - 1))
            except:
                sys.stderr.write('%s' % e)

    def command_help(self):
        sys.stdout.write("Available commands:\n")
        sys.stdout.write("   Blogit ls              list all posts\n")
        sys.stdout.write("   Blogit new             create a new post\n")
        sys.stdout.write("   Blogit edit <id>       edit a post\n")
        sys.stdout.write("   Blogit commit          commit current post\n")
        sys.stdout.write("   Blogit push            publish post\n")
        sys.stdout.write("   Blogit unpush          unpublish post\n")
        sys.stdout.write("   Blogit rm <id>         remove a post\n")
        sys.stdout.write("   Blogit cat[egories]    list categories\n")
        sys.stdout.write("   Blogit tags            list tags\n")
        sys.stdout.write("   Blogit help            display this notice\n")

    def command_ls(self):
        try:
            allposts = self.client.metaWeblog.getRecentPosts('',
                    self.blog_username, self.blog_password)
            if not allposts:
                sys.stderr.write("There are no posts.")
                return
            vim.command('botright new')
            self.current_post = None
            vim.current.buffer[0] = "%sID    Date%sTitle" % \
                    ( ' ' * ( len(allposts[0]['postid']) - 2 ),
                    ( ' ' * len(self.DateTime_to_str(
                    allposts[0]['date_created_gmt'], '%x')) ) )
            format = '%%%dd    %%s    %%s' % max(2, len(allposts[0]['postid']))
            for p in allposts:
                vim.current.buffer.append(format % (int(p['postid']),
                        self.DateTime_to_str(p['date_created_gmt'], '%x'),
                        p['title'].encode('utf-8')))
            vim.command('setlocal buftype=nofile bufhidden=wipe nobuflisted ' +
                    'noswapfile syntax=blogsyntax nomodifiable nowrap')
            vim.current.window.cursor = (2, 0)
            vim.command('nnoremap <buffer> <enter> :py blogit.list_edit()<cr>')
            vim.command('nnoremap <buffer> gf :py blogit.list_edit()<cr>')
        except Exception, err:
            sys.stderr.write("An error has occured: %s" % err)

    def list_edit(self):
        try:
            row,col = vim.current.window.cursor
            id = vim.current.buffer[row-1].split()[0]
            vim.command('bdelete')
            self.command_edit(int(id))
        except Exception:
            return

    def command_edit(self, id):
        try:
            id = int(id)
        except ValueError:
            sys.stderr.write("'id' must be an integer value.")
            return

        try:
            post = self.getPost(id)
        except Fault, e:
            sys.stderr.write('Blogit Fault: ' + e.faultString)
        else:
            vim.command('enew')
            self.display_post(post)

    def command_new(self):
        username = self.client.blogger.getUserInfo(
                '', self.blog_username, self.blog_password)['firstname']
        vim.command('enew')
        self.display_post({'wp_author_display_name': username,
                           'postid': '',
                           'title': '',
                           'categories': '',
                           'mt_keywords': '',
                           'date_created_gmt': '',
                           'description': '',
                           'mt_text_more': '',
                           'post_status': 'draft',
                         })

    def display_post(self, post):
        vim.current.buffer[:] = None
        vim.command("setlocal ft=mail completefunc=CompleteCategories")
        vim.current.buffer[0] = 'From: %s' % \
                post['wp_author_display_name'].encode('utf-8')
        vim.current.buffer.append('Post-Id: %s' % post['postid'])
        vim.current.buffer.append('Subject: %s' % post['title'].encode('utf-8'))
        vim.current.buffer.append('Categories: %s' % \
                ", ".join(post["categories"]).encode("utf-8"))
        if self.have_tags:
            vim.current.buffer.append('Tags: %s' % \
                    post["mt_keywords"].encode("utf-8"))
        vim.current.buffer.append('Date: %s' % self.DateTime_to_str(
                post['date_created_gmt']))
        vim.current.buffer.append('')
        content = self.unformat(post["description"].encode("utf-8"))
        for line in content.split('\n'):
            vim.current.buffer.append(line)

        if post['mt_text_more']:
            vim.current.buffer.append('')
            vim.current.buffer.append('<!--more-->')
            vim.current.buffer.append('')
            content = self.unformat(post["mt_text_more"].encode("utf-8"))
            for line in content.split('\n'):
                vim.current.buffer.append(line)

        vim.current.window.cursor = (8, 0)
        vim.command('set nomodified')
        vim.command('set textwidth=0')
        self.current_post = post

    def str_to_DateTime(self, text=''):
        if text == '':
            text = localtime()
        else:
            text = strptime(text, '%c')
        return DateTime(strftime('%Y%m%dT%H:%M:%S', gmtime(mktime(text))))

    def DateTime_to_str(self, date, format='%c'):
        try:
            return strftime(format, localtime(timegm(strptime(str(date),
                                              '%Y%m%dT%H:%M:%S'))))
        except ValueError:
            return ''

    def getPost(self, id):
        return self.client.metaWeblog.getPost(id, self.blog_username,
                                                  self.blog_password)

    def getMeta(self, name):
        n = self.getLine(name)
        if not n:
            return ''

        r = re.compile('^%s: (.*)' % name)
        m = r.match(vim.current.buffer[n])
        if m:
            return m.group(1)

        return ''

    def getLine(self, name):
        r = re.compile('^%s: (.*)' % name)
        for n, line in enumerate(vim.current.buffer):
            if line == '':
                return 0
            m = r.match(line)
            if m:
                return n

        return 0

    def getText(self, start_text):
        """

        Can raise FilterException.
        """
        text = '\n'.join(vim.current.buffer[start_text:])
        return map(self.format, text.split('\n<!--more-->\n\n'))

    def unformat(self, text):
        try:
            return self.format(text, 'blogit_unformat')
        except self.FilterException, e:
            sys.stderr.write(e.message)
            return e.input_text

    def format(self, text, vim_var='blogit_format'):
        """ Filter text with command in vim_var.

        Can raise FilterException.
        """
        if not vim.eval('exists("%s")' % vim_var) != '0':
            return text
        try:
            filter = vim.eval(vim_var)
            p = Popen(filter, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE)
            p.stdin.write(text)
            p.stdin.close()
            if p.wait():
                raise self.FilterException(p.stderr.read(), text, filter)
            return p.stdout.read()
        except self.FilterException:
            raise
        except Exception, e:
            raise self.FilterException(e.message, text, filter)

    def command_commit(self):
        self.sendArticle()

    def command_push(self):
        self.sendArticle(push=1)

    def command_unpush(self):
        self.sendArticle(push=0)

    def sendArticle(self, push=None):
        if self.current_post is None:
            sys.stderr.write("Not editing a post.")
            return
        try:
            vim.command('set nomodified')
            start_text = 0
            for line in vim.current.buffer:
                start_text += 1
                if line == '':
                    break

            post = self.current_post.copy()

            post['title'] = self.getMeta('Subject')
            post['wp_author_display_name'] = self.getMeta('From')
            post['categories'] = self.getMeta('Categories').split(', ')
            if self.have_tags:
                post['mt_keywords'] = self.getMeta('Tags')

            textl = self.getText(start_text)
            post['description'] = textl[0]
            if len(textl) > 1:
                post['mt_text_more'] = textl[1]

            if push is None and self.current_post['post_status'] == 'publish':
                post['date_created_gmt'] = \
                        self.str_to_DateTime(self.getMeta('Date'))
            else:
                post['date_created_gmt'] = self.str_to_DateTime()

            if push == 1:
                post['post_status'] = 'publish'
            elif push == 0:
                post['post_status'] = 'draft'
            else:
                post['post_status'] = self.current_post['post_status']
                push = 0

            strid = self.getMeta('Post-Id')

            if strid == '':
                strid = self.client.metaWeblog.newPost('', self.blog_username,
                                                self.blog_password, post, push)
            else:
                self.client.metaWeblog.editPost(strid, self.blog_username,
                                                self.blog_password, post, push)
            self.display_post(self.getPost(strid))
        except self.FilterException, e:
            sys.stderr.write(e.message)
        except Fault, e:
            sys.stderr.write(e.faultString)

    def command_rm(self, id):
        try:
            id = int(id)
        except ValueError:
            sys.stderr.write("'id' must be an integer value.")
            return

        if self.current_post and int(self.current_post['postid']) == int(id):
            vim.command('bdelete')
            self.current_post = None
        try:
            self.client.metaWeblog.deletePost('', id, self.blog_username,
                                              self.blog_password)
        except Fault, e:
            sys.stderr.write(e.faultString)
            return
        sys.stdout.write('Article removed')

    def command_categories(self):
        sys.stdout.write('Categories:\n  ' + '\n  '.join(self.getCategories())
                         + '\n')

    command_cat = command_categories

    def command_tags(self):
        tags = [ tag['name'] for tag in self.client.wp.getTags('',
                    self.blog_username, self.blog_password) ]
        vim.command('let s:used_tags = %s' % tags)
        sys.stdout.write('Tags:\n' + ', '.join(tags))

    def getCategories(self):
        """ Returns a list of used categories from the server (slow).

        Side effect: Sets vim variable s:used_categories for omni-completion.
        """
        categories = [ cat['categoryName']
                for cat in self.client.wp.getCategories('',
                    self.blog_username, self.blog_password) ]
        vim.command('let s:used_categories = %s' % categories)
        return categories

    @property
    def blog_username(self):
        return vim.eval(self.blog_name + '_username')

    @property
    def blog_password(self):
        return vim.eval(self.blog_name + '_password')

    @property
    def blog_url(self):
        return vim.eval(self.blog_name + '_url')

    @property
    def have_tags(self):
        return vim.eval("!exists('%(name)s_tags') || %(name)s_tags" % \
                { 'name': self.blog_name } ) != '0'

    @property
    def blog_name(self):
        if vim.eval("exists('b:blog_name')") != '0':
            return vim.eval('b:blog_name')
        elif vim.eval("exists('blog_name')") != '0':
            return vim.eval('blog_name')
        else:
            return 'blogit'


blogit = BlogIt()
