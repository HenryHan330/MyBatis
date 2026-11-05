-- ============================================================
-- MyBatis / MyBatis-Plus 个人笔记 —— 示例库、表与初始化数据
-- 说明：
--   1. 表结构按笔记中的 DDL 整理；笔记里以截图给出的表（t_act、t_car.status/owner）
--      按其正文出现的字段名补全，可直接整体执行。
--   2. 笔记中「参数处理」章节的 t_student(id,name,age,height,birth,sex)
--      与「高级映射」章节的 t_student(sid,sname,cid) 结构冲突，
--      这里把前者改名为 t_stu，其余保持原样。
--   3. 执行：mysql -uroot -p < docs/sql/init.sql
-- ============================================================

CREATE DATABASE IF NOT EXISTS `mybatis` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE `mybatis`;

-- ------------------------------------------------------------
-- 1. t_car：贯穿全笔记的主表（CRUD / 动态 SQL / MP）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `t_car`;
CREATE TABLE `t_car` (
  `id`          bigint       NOT NULL AUTO_INCREMENT COMMENT '主键自增',
  `car_num`     varchar(255) DEFAULT NULL COMMENT '车牌号',
  `brand`       varchar(255) DEFAULT NULL COMMENT '品牌',
  `guide_price` decimal(10,2) DEFAULT NULL COMMENT '指导价：万',
  `produce_time` char(10)    DEFAULT NULL COMMENT '出厂日期',
  `car_type`    varchar(255) DEFAULT NULL COMMENT '汽车类型：燃油车 电车 氢能源',
  -- 以下两列供 MyBatis-Plus 章节使用（枚举处理器 / JSON 处理器）
  `status`      int          DEFAULT 1   COMMENT '状态：1在售 2已售 3维修中 4报废',
  `owner`       json         DEFAULT NULL COMMENT '车主信息（JSON）',
  PRIMARY KEY (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '汽车表';

INSERT INTO `t_car` (car_num, brand, guide_price, produce_time, car_type, status) VALUES
('1001', '宝马520Li', 10.00, '2020-10-11', '燃油车', 1),
('1002', '宝马540Li', 30.00, '2021-11-11', '新能源', 2),
('1003', '比亚迪汉',   20.00, '2022-12-12', '氢能源', 3),
('1004', '宝马535Li', 50.00, '2023-01-01', '燃油车', 1),
('1005', '小米SU7',   30.00, '2024-02-02', '电车',   4);

-- ------------------------------------------------------------
-- 2. t_act：Web 三层架构 / 转账案例
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `t_act`;
CREATE TABLE `t_act` (
  `id`      bigint      NOT NULL AUTO_INCREMENT COMMENT '主键',
  `actno`   varchar(255) DEFAULT NULL COMMENT '账号',
  `balance` decimal(10,2) DEFAULT NULL COMMENT '余额',
  PRIMARY KEY (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '银行账户表';

INSERT INTO `t_act` (actno, balance) VALUES ('act-001', 5000), ('act-002', 5000);

-- ------------------------------------------------------------
-- 3. t_clazz / t_student：高级映射（多对一、一对多、延迟加载）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `t_student`;
DROP TABLE IF EXISTS `t_clazz`;
CREATE TABLE `t_clazz` (
  `cid`   int          NOT NULL COMMENT '班级编号',
  `cname` varchar(255) DEFAULT NULL COMMENT '班级名称',
  PRIMARY KEY (`cid`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '班级表';

INSERT INTO `t_clazz` (cid, cname) VALUES (1001, '高三1班'), (1002, '高三2班');

CREATE TABLE `t_student` (
  `sid`   int          NOT NULL AUTO_INCREMENT,
  `sname` varchar(255) DEFAULT NULL,
  `cid`   int          DEFAULT NULL,
  PRIMARY KEY (`sid`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '学生表';

INSERT INTO `t_student` (sname, cid) VALUES
('张三', 1001), ('李四', 1001), ('王五', 1001), ('赵六', 1002), ('钱七', 1002);

-- ------------------------------------------------------------
-- 4. t_stu：参数处理演示（原笔记中叫 t_student）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `t_stu`;
CREATE TABLE `t_stu` (
  `id`     bigint       NOT NULL AUTO_INCREMENT,
  `name`   varchar(255) DEFAULT NULL,
  `age`    int          DEFAULT NULL,
  `height` double       DEFAULT NULL,
  `birth`  date         DEFAULT NULL,
  `sex`    char(1)      DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '学生表（参数处理演示）';

INSERT INTO `t_stu` (name, age, height, birth, sex) VALUES
('张三', 45, 1.81, '1980-10-12', '男'),
('李四', 45, 1.79, '1980-10-12', '女');

-- ------------------------------------------------------------
-- 5. t_customer：MP @TableField 演示（属性名与字段名不一致 / 关键字冲突）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `t_customer`;
CREATE TABLE `t_customer` (
  `id`       bigint       NOT NULL AUTO_INCREMENT,
  `username` varchar(255) DEFAULT NULL,
  `is_vip`   varchar(255) DEFAULT NULL,
  `desc`     varchar(255) DEFAULT NULL COMMENT 'desc 是 MySQL 关键字，必须用 @TableField 指定',
  PRIMARY KEY (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '客户表';

INSERT INTO `t_customer` (username, is_vip, `desc`) VALUES ('张三', '1', 'VIP客户');

-- ------------------------------------------------------------
-- 6. t_wx：维修记录（MP 静态工具类 Db / 逻辑删除）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `t_wx`;
CREATE TABLE `t_wx` (
  `id`          bigint       NOT NULL AUTO_INCREMENT,
  `time`        char(10)     DEFAULT NULL COMMENT 'time 是关键字，实体类上要用 @TableField("`time`")',
  `cost`        decimal(10,2) DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL,
  `car_id`      bigint       DEFAULT NULL COMMENT '关联 t_car.id',
  `deleted`     int          NOT NULL DEFAULT 0 COMMENT '逻辑删除标记：0未删除 1已删除',
  PRIMARY KEY (`id`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '汽车维修记录表';

INSERT INTO `t_wx` (`time`, cost, description, car_id) VALUES
('2025-10-11', 300, '更换火花塞', 1),
('2025-10-12', 400, '小保养',     1),
('2025-10-13', 500, '大保养',     1);
