#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# P2P national network Pandora
# RU: P2P �������� ���� �������
#
# This program is distributed under the GNU GPLv2
# RU: ��� ��������� ���������������� ��� GNU GPLv2
# 2012 (c) Michael Galyuk
# RU: 2012 (c) ������ �����
# 2014 (c) Vladimir Bulanov
# RU: 2014 (c) �������� �������


# ====================================================================
# Pandora localization
# RU: ����������� �������

# Array of localization phrases
# RU: ������ ����������� ����
$lang_trans = {}

# Translation of the phrase
# RU: ������� �����
def _(frase)
  trans = $lang_trans[frase]
  if not trans or (trans.size==0) and frase and (frase.size>0)
    trans = frase
  end
  trans
end


# ====================================================================
require "#{File.dirname(__FILE__)}/p_utils"
require "#{File.dirname(__FILE__)}/p_logic"
require "#{File.dirname(__FILE__)}/p_crypt"
require "#{File.dirname(__FILE__)}/p_proto"
require "#{File.dirname(__FILE__)}/p_gmain"
