"""
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
" Version:      1.2
" Last Change:  2009 July 18
"
" Commands :
" ":Blogit ls"
"   Lists all articles in the blog
" ":Blogit new"
"   Opens page to write new article
" ":Blogit this"
"   Make current buffer a blog post
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
" ":Blogit tags"
"   Show tags and categories list
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
"       let blogit_url='https://your.path.to/xmlrpc.php'
"
"   In addition you can set these settings in your vimrc:
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
"   CTRL-X_CTRL-U). The list of them is gotten automatically on first
"   ":Blogit edit" and can be updated with ":Blogit tags".
"
"   To use tags your WordPress needs to have the UTW-RPC[3] plugin installed
"   (WordPress.com does).
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

function BlogitCompleteCategories(findstart, base)
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
# Lets the python unit test ignore eveything above this line (docstring). """
try:
    import vim
except ImportError:
    # Used outside of vim (for testing)
    from minimock import Mock
    vim = Mock('vim')
    import doctest
else:
    doctest = False
import xmlrpclib, sys, re
from time import mktime, strptime, strftime, localtime, gmtime
from calendar import timegm
from subprocess import Popen, CalledProcessError, PIPE
from xmlrpclib import DateTime, Fault, MultiCall
from inspect import getargspec
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
        """
        >>> xmlrpclib = Mock('xmlrpclib')
        >>> sys.stderr = Mock('stderr')
        >>> blogit.command('non-existant')
        Called vim.eval('blogit_url')
        Called stderr.write('No such command: non-existant')

        >>> def f(x): print 'got %s' % x
        >>> blogit.command_mocktest = f
        >>> blogit.command('mocktest')
        Called stderr.write('Command mocktest takes 0 arguments')

        >>> blogit.command('mocktest', 2)
        got 2
        """
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

    def list_comments(self):
        if vim.current.line.startswith('Status: '):
            self.getComments(self.current_post['postid'])

    def list_edit(self):
        """
        >>> vim.command = Mock('vim.command')
        >>> vim.current.window.cursor = (1, 2)
        >>> vim.current.buffer = [ '12 random text' ]
        >>> blogit.list_edit()
        Called vim.command('bdelete')
        Called vim.command('Blogit edit 12')

        >>> vim.current.buffer = [ 'no blog id 12' ]
        >>> blogit.command_new = Mock('self.command_new')
        >>> blogit.list_edit()
        Called vim.command('bdelete')
        Called self.command_new()
        """
        row, col = vim.current.window.cursor
        id = vim.current.buffer[row-1].split()[0]
        try:
            id = int(id)
        except ValueError:
            vim.command('bdelete')
            self.command_new()
        else:
            vim.command('bdelete')
            # To access vim s:variables we can't call this directly
            # via command_edit
            vim.command('Blogit edit %s' % id)

    meta_data_dict = { 'From': 'wp_author_display_name', 'Post-Id': 'postid',
            'Subject': 'title', 'Categories': 'categories',
            'Tags': 'mt_keywords', 'Date': 'date_created_gmt',
            'Status': 'blogit_status',
           }

    def display_post(self, post={}, new_text=None):
        def display_comment_count(d):
            if d == '':
                return u'new'
            comment_typ_count = [ '%s %s' % (key, text)
                    for key, text in ( ( 'awaiting_moderation', 'awaiting' ),
                            ( 'spam', 'spam' ) )
                    if d[key] > 0 ]
            if comment_typ_count == []:
                s = u''
            else:
                s = u' (%s)' % ', '.join(comment_typ_count)
            return ( u'%(post_status)s \u2013 %(total_comments)s Comments' + s ) % d

        default_post = { 'post_status': 'draft',
                         self.meta_data_dict['From']: self.blog_username }
        default_post.update(post)
        post = default_post
        meta_data_f_dict = { 'Date': self.DateTime_to_str,
                   'Categories': lambda L: ', '.join(L),
                   'Status': display_comment_count
                 }
        vim.current.buffer[:] = None
        vim.command("setlocal ft=mail completefunc=BlogitCompleteCategories")
        for label in [ 'From', 'Post-Id', 'Subject', 'Status', 'Categories',
                'Tags', 'Date' ]:
            try:
                val = post[self.meta_data_dict[label]]
            except KeyError:
                val = ''
            if label in meta_data_f_dict:
                val = meta_data_f_dict[label](val)
            vim.current.buffer.append('%s: %s' % ( label,
                    unicode(val).encode('utf-8') ))
        vim.current.buffer[0] = None
        vim.current.buffer.append('')
        if new_text is None:
            content = self.unformat(post.get('description', '')\
                        .encode("utf-8")).split('\n')
        else:
            content = new_text
        for line in content:
            vim.current.buffer.append(line)

        if post.get('mt_text_more'):
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
        vim.command('nnoremap <buffer> gf :py blogit.list_comments()<cr>')

    @staticmethod
    def str_to_DateTime(text='', format='%c'):
        """
        >>> BlogIt.str_to_DateTime()                    #doctest: +ELLIPSIS
        <DateTime ...>

        >>> BlogIt.str_to_DateTime('Sun Jun 28 19:38:58 2009',
        ...         '%a %b %d %H:%M:%S %Y')             #doctest: +ELLIPSIS
        <DateTime '20090628T17:38:58' at ...>

        >>> BlogIt.str_to_DateTime(BlogIt.DateTime_to_str(
        ...         DateTime('20090628T17:38:58')))     #doctest: +ELLIPSIS
        <DateTime '20090628T17:38:58' at ...>
        """
        if text == '':
            text = localtime()
        else:
            text = strptime(text, format)
        return DateTime(strftime('%Y%m%dT%H:%M:%S', gmtime(mktime(text))))

    @staticmethod
    def DateTime_to_str(date, format='%c'):
        """
        >>> BlogIt.DateTime_to_str(DateTime('20090628T17:38:58'),
        ...         '%a %b %d %H:%M:%S %Y')
        'Sun Jun 28 19:38:58 2009'

        >>> BlogIt.DateTime_to_str('invalid input')
        ''
        """
        try:
            return strftime(format, localtime(timegm(strptime(str(date),
                                              '%Y%m%dT%H:%M:%S'))))
        except ValueError:
            return ''

    def getPost(self, id):
        """
        >>> blogit.blog_username, blogit.blog_password = 'user', 'password'
        >>> xmlrpclib.MultiCall = Mock('xmlrpclib.MultiCall', returns=Mock(
        ...         'multicall', returns=[{'post_status': 'draft'}, {}]))
        >>> d = blogit.getPost(42)    #doctest: +ELLIPSIS
        Called xmlrpclib.MultiCall(<Mock 0x... client>)
        Called multicall.metaWeblog.getPost(42, 'user', 'password')
        Called multicall.wp.getCommentCount('', 'user', 'password', 42)
        Called vim.eval('s:used_tags == [] || s:used_categories == []')
        Called multicall()
        >>> sorted(d.items())
        [('blogit_status', {'post_status': 'draft'}), ('post_status', 'draft')]
        """
        username, password = self.blog_username, self.blog_password
        multicall = xmlrpclib.MultiCall(self.client)
        multicall.metaWeblog.getPost(id, username, password)
        multicall.wp.getCommentCount('', username, password, id)
        if vim.eval('s:used_tags == [] || s:used_categories == []') == '1':
            multicall.wp.getCategories('', username, password)
            multicall.wp.getTags('', username, password)
            d, comments, categories, tags = tuple(multicall())
            vim.command('let s:used_tags = %s' % [ tag['name']
                    for tag in tags ])
            vim.command('let s:used_categories = %s' % [ cat['categoryName']
                    for cat in categories ])
        else:
            d, comments = tuple(multicall())
        comments['post_status'] = d['post_status']
        d['blogit_status'] = comments
        return d

    def getComments(self, id, offset=0):
        """
        >>> vim.command = Mock('vim.command')
        >>> blogit.client = Mock('client')
        >>> blogit.client.wp.getComments = Mock('getComments', returns=[])
        >>> blogit.getComments(42)
        Called vim.command('enew')
        Called vim.eval('blogit_username')
        Called vim.eval('blogit_password')
        Called getComments(
            '',
            'http://example.com',
            'http://example.com',
            {'post_id': 42, 'number': 1000, 'offset': 0})
        Called vim.command('set nomodifiable')
        """
        # TODO
        vim.command('enew')
        for comment in self.client.wp.getComments('', blogit.blog_username,
                blogit.blog_password, {'post_id': id,
                                       'offset': offset,
                                       'number': 1000}):
            for header in ( 'status', 'author', 'comment_id', 'parent',
                        'date_created_gmt', 'type'  ):
                vim.current.buffer.append('%s: %s' %
                        ( header, comment[header] ))
            vim.current.buffer.append('')
            for line in comment['content'].split('\n'):
                vim.current.buffer.append(line.encode('utf-8'))
            vim.current.buffer.append('=' * 78)
            vim.current.buffer.append('')
        vim.command('set nomodifiable')

    def getMeta(self):
        """
        >>> vim.current.buffer = [ 'tag: value', '', 'body: novalue' ]
        >>> list(blogit.getMeta())
        [('tag', 'value')]
        """
        r = re.compile('^(.*?): (.*)$')
        for line in vim.current.buffer:
            if line.rstrip() == '':
                return
            m = r.match(line)
            if m:
                yield m.group(1, 2)

    def getText(self, start_text):
        r"""

        Can raise FilterException.

        >>> vim.current.buffer = [ 'one', 'two', 'tree', 'four' ]

        >>> blogit.getText(0)
        Called vim.eval('exists("blogit_format")')
        ['one\ntwo\ntree\nfour']

        >>> blogit.getText(1)
        Called vim.eval('exists("blogit_format")')
        ['two\ntree\nfour']

        >>> blogit.getText(4)
        Called vim.eval('exists("blogit_format")')
        ['']

        >>> vim.eval = Mock('vim.eval', returns_iter=['1', 'sort'])
        >>> blogit.getText(0)
        Called vim.eval('exists("blogit_format")')
        Called vim.eval('blogit_format')
        ['four\none\ntree\ntwo\n']

        >>> vim.eval = Mock('vim.eval', returns_iter=['1', 'false'])
        >>> blogit.getText(0)     # can't get this to work :'(
        Traceback (most recent call last):
            ...
        FilterException
        """
        text = '\n'.join(vim.current.buffer[start_text:])
        return map(self.format, text.split('\n<!--more-->\n\n'))

    def unformat(self, text):
        r"""
        >>> old = vim.eval
        >>> vim.eval = Mock('vim.eval', returns_iter=[ '1', 'false' ])
        >>> blogit.unformat('some random text')
        ...         #doctest: +NORMALIZE_WHITESPACE
        Called vim.eval('exists("blogit_unformat")')
        Called vim.eval('blogit_unformat')
        Called stderr.write('Blogit: Error happend while filtering
                with:false\n')
        'some random text'

        >>> vim.eval = old
        """
        try:
            return self.format(text, 'blogit_unformat')
        except self.FilterException, e:
            sys.stderr.write(e.message)
            return e.input_text

    def format(self, text, vim_var='blogit_format'):
        r""" Filter text with command in vim_var.

        Can raise FilterException.

        >>> blogit.format('some random text')
        Called vim.eval('exists("blogit_format")')
        'some random text'

        >>> old = vim.eval
        >>> vim.eval = Mock('vim.eval', returns_iter=[ '1', 'false' ])
        >>> blogit.format('some random text')
        Traceback (most recent call last):
            ...
        FilterException

        >>> vim.eval = Mock('vim.eval', returns_iter=[ '1', 'rev' ])
        >>> blogit.format('')
        Called vim.eval('exists("blogit_format")')
        Called vim.eval('blogit_format')
        ''

        >>> vim.eval = Mock('vim.eval', returns_iter=[ '1', 'rev' ])
        >>> blogit.format('some random text')
        Called vim.eval('exists("blogit_format")')
        Called vim.eval('blogit_format')
        'txet modnar emos\n'

        >>> vim.eval = Mock('vim.eval', returns_iter=[ '1', 'rev' ])
        >>> blogit.format('some random text\nwith a second line')
        Called vim.eval('exists("blogit_format")')
        Called vim.eval('blogit_format')
        'txet modnar emos\nenil dnoces a htiw\n'

        >>> vim.eval = old

        """
        if not vim.eval('exists("%s")' % vim_var) == '1':
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

    def sendArticle(self, push=None):

        def sendPost(postid, post, push):
            """ Unify newPost and editPost from the metaWeblog API. """
            if postid == '':
                postid = self.client.metaWeblog.newPost('', self.blog_username,
                                                self.blog_password, post, push)
            else:
                self.client.metaWeblog.editPost(postid, self.blog_username,
                                                self.blog_password, post, push)
            return postid

        def date_from_meta(str_date):
            if push is None and self.current_post['post_status'] == 'publish':
                return self.str_to_DateTime(str_date)
            return self.str_to_DateTime()

        def split_comma(x): return x.split(', ')

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
            meta_data_f_dict = { 'Categories': split_comma,
                                 'Date': date_from_meta }

            for label, value in self.getMeta():
                if self.meta_data_dict[label].startswith('blogit_'):
                    continue
                if label in meta_data_f_dict:
                    value = meta_data_f_dict[label](value)
                post[self.meta_data_dict[label]] = value

            push_dict = { 0: 'draft', 1: 'publish',
                          None: self.current_post['post_status'] }
            post['post_status'] = push_dict[push]
            if push is None:
                push = 0

            textl = self.getText(start_text)
            post['description'] = textl[0]
            if len(textl) > 1:
                post['mt_text_more'] = textl[1]

            postid = sendPost(post['postid'], post, push)
            self.display_post(self.getPost(postid))
        except self.FilterException, e:
            sys.stderr.write(e.message)
        except Fault, e:
            sys.stderr.write(e.faultString)

    @property
    def blog_username(self):
        return vim.eval(self.blog_name + '_username')

    @property
    def blog_password(self):
        return vim.eval(self.blog_name + '_password')

    @property
    def blog_url(self):
        """
        >>> vim.eval.mock_returns = 'http://example.com'
        >>> blogit.blog_name='blogit'
        >>> blogit.blog_url
        Called vim.eval('blogit_url')
        'http://example.com'
        """
        return vim.eval(self.blog_name + '_url')

    @property
    def blog_name(self):
        """
        >>> vim.eval = Mock('vim.eval')
        >>> blogit.blog_name
        Called vim.eval("exists('b:blog_name')")
        Called vim.eval("exists('blog_name')")
        'blogit'

        """
        if vim.eval("exists('b:blog_name')") == '1':
            return vim.eval('b:blog_name')
        elif vim.eval("exists('blog_name')") == '1':
            return vim.eval('blog_name')
        else:
            return 'blogit'

    vimcommand_help = []

    def vimcommand(f, register_to=vimcommand_help):
        r"""
        >>> class C:
        ...     def command_f(self):
        ...         ''' A method. '''
        ...         print "f should not be executed."
        ...     def command_g(self, one, two):
        ...         ''' A method with options. '''
        ...         print "g should not be executed."
        ...
        >>> L = []
        >>> BlogIt.vimcommand(C.command_f, L)
        <unbound method C.command_f>
        >>> L
        [':Blogit f                  A method. \n']

        >>> BlogIt.vimcommand(C.command_g, L)
        <unbound method C.command_g>
        >>> L     #doctest: +NORMALIZE_WHITESPACE
        [':Blogit f                  A method. \n',
         ':Blogit g <one> <two>      A method with options. \n']

        """

        def getArguments(func, skip=0):
            """
            Get arguments of a function as a string.
            skip is the number of skipped arguments.
            """
            skip += 1
            args, varargs, varkw, defaults = getargspec(func)
            arguments = list(args)
            if defaults:
                index = len(arguments)-1
                for default in reversed(defaults):
                    arguments[index] += "=%s" % default
                    index -= 1
            if varargs:
                arguments.append("*" + varargs)
            if varkw:
                arguments.append("**" + varkw)
            return "".join((" <%s>" % s for s in arguments[skip:]))

        command = ( f.func_name.replace('command_', ':Blogit ') +
                getArguments(f) )
        register_to.append('%-25s %s\n' % ( command, f.__doc__ ))
        return f

    @vimcommand
    def command_ls(self):
        """ list all posts """
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

    @vimcommand
    def command_new(self):
        """ create a new post """
        vim.command('enew')
        self.display_post()

    @vimcommand
    def command_this(self):
        """ make this a blog post """
        if self.current_post is None:
            self.display_post(new_text=vim.current.buffer[:])
        else:
            sys.stderr.write("Already editing a post.")

    @vimcommand
    def command_edit(self, id):
        """ edit a post """
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

    @vimcommand
    def command_commit(self):
        """ commit current post """
        self.sendArticle()

    @vimcommand
    def command_push(self):
        """ publish post """
        self.sendArticle(push=1)

    @vimcommand
    def command_unpush(self):
        """ unpublish post """
        self.sendArticle(push=0)

    @vimcommand
    def command_rm(self, id):
        """ remove a post """
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

    @vimcommand
    def command_tags(self):
        """ update and list tags and categories"""
        username, password = self.blog_username, self.blog_password
        multicall = xmlrpclib.MultiCall(self.client)
        multicall.wp.getCategories('', username, password)
        multicall.wp.getTags('', username, password)
        categories, tags = tuple(multicall())
        tags = [ tag['name'] for tag in tags ]
        categories = [ cat['categoryName'] for cat in categories ]
        vim.command('let s:used_tags = %s' % tags)
        vim.command('let s:used_categories = %s' % categories)
        sys.stdout.write('\n \n \nCategories\n==========\n \n' + ', '.join(categories))
        sys.stdout.write('\n \n \nTags\n====\n \n' + ', '.join(tags))

    @vimcommand
    def command_help(self):
        """ display this notice """
        sys.stdout.write("Available commands:\n")
        for f in self.vimcommand_help:
            sys.stdout.write('   ' + f)

    # needed for testing. Prevents beeing used as a decorator if it isn't at
    # the end.
    vimcommand = staticmethod(vimcommand)


blogit = BlogIt()

if doctest:
    doctest.testmod()
