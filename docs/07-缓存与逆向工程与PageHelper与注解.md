# 07 缓存、逆向工程、PageHelper、注解式开发

> 本篇是「工具篇」，四个知识点都够用就行，不过度展开。

## 1. 缓存

### 1.1 一级缓存（`SqlSession` 级别，默认开启）

同一个 `SqlSession` 里，**同一条 SQL + 同样的参数**，第二次查询不再打数据库，直接返回缓存对象。

```java
SqlSession sqlSession = SqlSessionUtil.openSession();
CarMapper mapper = sqlSession.getMapper(CarMapper.class);

Car c1 = mapper.selectById(1L);   // 发 SQL
Car c2 = mapper.selectById(1L);   // 不走数据库，直接命中一级缓存
System.out.println(c1 == c2);     // true —— 同一个对象
```

**一级缓存什么时候失效**

| 操作 | 说明 |
| --- | --- |
| 执行 `insert/update/delete` | 会自动 `clearCache()`（保证数据一致） |
| `sqlSession.commit()` / `close()` | 提交或关闭即清空 |
| 手动 `sqlSession.clearCache()` | 主动清空 |
| 换一个 `SqlSession` | 一级缓存是会话级的，另一个会话看不到 |

> 想关掉：`<setting name="localCacheScope" value="STATEMENT"/>`（每条语句一个作用域，等于不使用一级缓存）。
> **注意**：一级缓存用不好会出现「查到的还是旧数据」（在分布式/多实例下尤其明显），生产上要留意。

### 1.2 二级缓存（`namespace` 级别，默认关闭）

**开启三步**

1. `mybatis-config.xml`：

```xml
<settings>
    <setting name="cacheEnabled" value="true"/>   <!-- 默认就是 true -->
</settings>
```

2. Mapper XML 里加 `<cache/>`：

```xml
<mapper namespace="com.jkweilai.mybatis.mapper.CarMapper">
    <cache eviction="LRU"
           flushInterval="60000"
           size="1024"
           readOnly="false"/>
</mapper>
```

3. 实体类**实现 `Serializable`**（`readOnly=false` 时会序列化缓存对象）。

| 属性 | 含义 |
| --- | --- |
| `eviction` | 回收策略：`LRU`（默认）、`FIFO`、`SOFT`、`WEAK` |
| `flushInterval` | 刷新间隔（毫秒），不写则没有刷新间隔，只在增删改时刷新 |
| `size` | 最多缓存多少个对象（默认 1024） |
| `readOnly` | `true` 只读（返回同一实例，快，但不安全）；`false` 可读写（序列化副本） |

**关键特性**

- 二级缓存是 **`namespace` 级**，跨 `SqlSession`（同一个 `SqlSessionFactory`）共享。
- **必须等 `SqlSession` 关闭或提交之后**，缓存才会真正写入；换言之，事务没提交别人读不到。
- 不同 `namespace` 之间**不共享**缓存；多表关联查询时，**某个表的更新不会自动清空另一个 namespace 的缓存**，这是使用二级缓存最大的坑（容易读到脏数据）。
- 一般项目里，**推荐用 Redis 做分布式缓存**，MyBatis 二级缓存只在单机小项目里用。

## 2. 逆向工程（MBG，MyBatis Generator）

作用：**根据表结构自动生成** POJO、Mapper 接口、Mapper XML。

### 2.1 pom.xml 加插件

```xml
<plugin>
    <groupId>org.mybatis.generator</groupId>
    <artifactId>mybatis-generator-maven-plugin</artifactId>
    <version>1.4.1</version>
    <configuration>
        <overwrite>true</overwrite>
        <configurationFile>src/main/resources/generatorConfig.xml</configurationFile>
    </configuration>
    <dependencies>
        <dependency>
            <groupId>mysql</groupId>
            <artifactId>mysql-connector-java</artifactId>
            <version>8.0.24</version>
        </dependency>
    </dependencies>
</plugin>
```

### 2.2 generatorConfig.xml 关键片段

```xml
<generatorConfiguration>
    <context id="DB2Tables" targetRuntime="MyBatis3Simple">
        <commentGenerator>
            <property name="suppressAllComments" value="true"/>
        </commentGenerator>

        <jdbcConnection driverClass="com.mysql.cj.jdbc.Driver"
                        connectionURL="jdbc:mysql://localhost:3306/mybatis"
                        userId="root" password="root"/>

        <javaTypeResolver>
            <property name="forceBigDecimals" value="false"/>
        </javaTypeResolver>

        <!-- 生成的实体类放哪 -->
        <javaModelGenerator targetPackage="com.jkweilai.mybatis.pojo" targetProject="src/main/java">
            <property name="enableSubPackages" value="true"/>
        </javaModelGenerator>

        <!-- 生成的 Mapper XML 放哪 -->
        <sqlMapGenerator targetPackage="com.jkweilai.mybatis.mapper" targetProject="src/main/resources">
            <property name="enableSubPackages" value="true"/>
        </sqlMapGenerator>

        <!-- 生成的 Mapper 接口放哪 -->
        <javaClientGenerator type="XMLMAPPER" targetPackage="com.jkweilai.mybatis.mapper" targetProject="src/main/java">
            <property name="enableSubPackages" value="true"/>
        </javaClientGenerator>

        <!-- 要生成哪些表 -->
        <table tableName="t_car" domainObjectName="Car"/>
    </context>
</generatorConfiguration>
```

### 2.3 运行

IDEA 右侧 Maven → `mybatis-generator` → `mybatis-generator:generate`，或命令行：

```bash
mvn mybatis-generator:generate
```

**`targetRuntime` 的两种值**

| 值 | 生成内容 |
| --- | --- |
| `MyBatis3Simple` | 只生成基础 CRUD（`selectByPrimaryKey`、`insert`…），**够用且干净** |
| `MyBatis3` | 生成「Example」系列（`selectByExample`、`CarExample`…），功能强但类很臃肿 |

> 现在已经没人手写这套配置了：MyBatis-Plus 用户直接装 **MyBatisX** 插件，在表上右键就能生成。

## 3. PageHelper 分页插件

### 3.1 手写分页有多烦

```sql
select * from t_car limit ?, ?                     -- 当前页数据
select count(*) from t_car where ...               -- 总条数（还要再拼一遍 where）
```

除了数据，前端还需要「总条数、总页数、当前页、是否有下一页」，全靠自己算。

### 3.2 用 PageHelper

**第一步：依赖**

```xml
<dependency>
    <groupId>com.github.pagehelper</groupId>
    <artifactId>pagehelper</artifactId>
    <version>5.3.1</version>
</dependency>
```

**第二步：在 `mybatis-config.xml` 里注册插件**（`plugins` 必须放在 `typeAliases` 之后、`environments` 之前）

```xml
<plugins>
    <plugin interceptor="com.github.pagehelper.PageInterceptor"></plugin>
</plugins>
```

**第三步：使用**

```java
@Test
public void testPageHelper() {
    SqlSession sqlSession = SqlSessionUtil.openSession();
    CarMapper mapper = sqlSession.getMapper(CarMapper.class);

    // 1. 开启分页（页码从 1 开始）
    PageHelper.startPage(2, 2);

    // 2. 紧接着的第一条查询会被自动分页
    List<Car> cars = mapper.selectAll();

    // 3. 用 PageInfo 拿到分页信息
    PageInfo<Car> pageInfo = new PageInfo<>(cars);
    System.out.println("总条数：" + pageInfo.getTotal());
    System.out.println("总页数：" + pageInfo.getPages());
    System.out.println("当前页：" + pageInfo.getPageNum());
    System.out.println("每页条数：" + pageInfo.getPageSize());
    System.out.println("是否有下一页：" + pageInfo.isHasNextPage());
    System.out.println("数据：" + pageInfo.getList());
}
```

**原理**：`PageHelper.startPage()` 把分页参数放进 `ThreadLocal`，插件拦截下一条执行的 SQL，动态拼上 `limit`，并额外执行一次 `count` 查询。

**坑**

| 坑 | 说明 |
| --- | --- |
| `startPage` 后没紧跟查询 | 分页参数会「留」给下一条毫不相干的 SQL，导致结果莫名其妙 |
| 中间插了别的查询 | 同上。`startPage` 与目标查询**必须紧挨着** |
| 分页没生效（没有 `limit`） | 插件没注册 / 版本与 MyBatis 不兼容 |
| 对 `resultMap` 里有集合的查询分页 | `count` 语句可能算错（关联行被重复计数） |

> MyBatis-Plus 有自己的 `PaginationInnerInterceptor`，不需要 PageHelper，见 [11 篇](11-MP-进阶特性.md)。

## 4. 注解式开发

把 SQL 直接写在 Mapper 接口的方法上，不用 XML。

### 4.1 基本 CRUD

```java
public interface CarMapper {

    @Select("select * from t_car where id = #{id}")
    Car selectById(Long id);

    @Insert("insert into t_car values(null, #{carNum}, #{brand}, #{guidePrice}, #{produceTime}, #{carType})")
    @Options(useGeneratedKeys = true, keyProperty = "id")
    int insert(Car car);

    @Update("update t_car set brand = #{brand} where id = #{id}")
    int updateById(Car car);

    @Delete("delete from t_car where id = #{id}")
    int deleteById(Long id);
}
```

### 4.2 解决列名与属性名不一致：`@Results`

```java
@Select("select * from t_car where id = #{id}")
@Results(id = "carResultMap", value = {
        @Result(property = "id",          column = "id", id = true),
        @Result(property = "carNum",      column = "car_num"),
        @Result(property = "guidePrice",  column = "guide_price"),
        @Result(property = "produceTime", column = "produce_time"),
        @Result(property = "carType",     column = "car_type")
})
Car selectById(Long id);

// 复用上面的映射
@Select("select * from t_car")
@ResultMap("carResultMap")
List<Car> selectAll();
```

### 4.3 一对一 / 一对多：`@One` / `@Many`

```java
// 多对一
@Select("select * from t_student where sid = #{sid}")
@Results({
        @Result(property = "sid", column = "sid", id = true),
        @Result(property = "clazz", column = "cid",
                one = @One(select = "com.jkweilai.mybatis.mapper.ClazzMapper.selectById",
                           fetchType = FetchType.LAZY))
})
Student selectById(Long sid);

// 一对多
@Select("select * from t_clazz where cid = #{cid}")
@Results({
        @Result(property = "cid", column = "cid", id = true),
        @Result(property = "students", column = "cid",
                many = @Many(select = "com.jkweilai.mybatis.mapper.StudentMapper.selectByCid"))
})
Clazz selectClazzWithStudents(Long cid);
```

### 4.4 注解 vs XML：怎么选

| | 注解 | XML |
| --- | --- | --- |
| 简单 SQL（单表 CRUD） | ✅ 直观、无文件切换 | 稍啰嗦 |
| 动态 SQL（`if`/`foreach`） | ❌ 要用 `<script>` 包一大段字符串，几乎不可读 | ✅ 首选 |
| 复杂结果映射 | 注解堆一堆 `@Results` | ✅ `resultMap` 更清晰 |
| 维护性 | SQL 改一行要重新编译 | 改 XML 不用编译 |

**实践结论**：**简单 SQL 用注解，复杂 SQL 用 XML**，两者可以在同一个 Mapper 里混用。
（Spring Boot + MyBatis-Plus 项目里，注解 + Wrapper 已经能覆盖绝大多数单表场景。）

